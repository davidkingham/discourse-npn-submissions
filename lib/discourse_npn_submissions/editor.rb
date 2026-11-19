# frozen_string_literal: true

module DiscourseNpnSubmissions
  # Edits an already-published submission through the submission form: the
  # stored form data is replaced with the new form state, the first post is
  # rebuilt with the same PostBuilder that created it, and the change is saved
  # with PostRevisor so Discourse keeps its normal edit history.
  #
  # Rules:
  #   * Only the submission's author (or staff) may edit, and only while
  #     Discourse itself would let them edit the first post (edit time limit,
  #     locked/archived topics, silenced users all still apply).
  #   * On critique-style posts (image, weekly challenge, project, new member
  #     image) the media is locked once anyone else has replied. Critiques and
  #     visual annotations refer to the original images; after that point a
  #     new image belongs in the "Revised Version" flow
  #     (discourse-npn-revised-critique). Text and tags stay editable.
  #     Introductions and help requests never lock.
  #   * A revised-version block at the top of the post is preserved as-is, and
  #     so is a project's image block (where project revisions are rendered)
  #     once media is locked.
  #   * A Weekly Challenge post keeps the challenge it was published under.
  #   * If the post was changed outside the form (a manual edit), the caller
  #     must pass `force: true` to overwrite it, after warning the user.
  module Editor
    class NotFound < StandardError
    end

    class NotAllowed < StandardError
    end

    class NotEditable < StandardError
    end

    class ImagesLocked < StandardError
    end

    class EditedOutsideForm < StandardError
    end

    class Failed < StandardError
    end

    # Types whose form has an edit mode.
    EDITABLE_TYPES = Submission::SUBMISSION_TYPES

    # Types whose media locks once someone else replies: the types whose
    # images are critiqued and annotated.
    MEDIA_LOCK_TYPES = Submission::IMAGE_VERSION_TYPES

    # Topic metadata describing the original images. Left untouched on an edit
    # while media is locked: the critique-reply and revised-critique plugins
    # key on it, and the project payload's per-image ids are random, so a
    # rebuild would orphan existing project revisions.
    IMAGE_METADATA_KEYS = [
      TopicMetadata::CRITIQUE_IMAGE_VERSION_SCHEMA_KEY,
      TopicMetadata::ORIGINAL_PRIMARY_UPLOAD_ID_KEY,
      TopicMetadata::ORIGINAL_PRIMARY_URL_KEY,
      TopicMetadata::ORIGINAL_UPLOAD_IDS_KEY,
      TopicMetadata::ORIGINAL_IMAGE_COUNT_KEY,
      TopicMetadata::PROJECT_SUBMISSION_DATA_KEY,
    ].freeze

    # Written by discourse-npn-revised-critique at the top of the first post.
    REVISED_BEGIN_MARKER = "<!-- revised-critique-image:begin -->"
    REVISED_END_MARKER = "<!-- revised-critique-image:end -->"

    # Fingerprint of the post body the form last wrote, kept in the
    # submission's `data` so a later edit can tell whether the post was
    # changed by hand in between.
    POSTED_BODY_KEY = "posted_body_sha1"

    module_function

    # Whether `user` may edit `submission` through the form right now. Cheap
    # enough for the topic view serializer.
    def editable_by?(user, submission, post: nil)
      return false if user.blank? || submission.blank?
      return false unless submission.status == "submitted" && submission.topic_id.present?
      return false if EDITABLE_TYPES.exclude?(submission.submission_type)
      return false unless submission.user_id == user.id || user.staff?

      post ||= first_post(submission)
      post.present? && Guardian.new(user).can_edit?(post)
    end

    # What the form needs to open in edit mode.
    def state(user:, submission_id:)
      submission, post = load!(user, submission_id)
      submission.weekly_challenge_snapshot = weekly_challenge_snapshot(post.topic)
      {
        submission: submission,
        images_locked: media_locked?(submission, post.topic),
        edited_outside_form: edited_outside_form?(submission, post),
      }
    end

    def call(user:, submission_id:, attrs:, force: false)
      submission, post = load!(user, submission_id)
      topic = post.topic
      snapshot = weekly_challenge_snapshot(topic)
      submission.weekly_challenge_snapshot = snapshot

      raise EditedOutsideForm if !force && edited_outside_form?(submission, post)

      locked = media_locked?(submission, topic)
      original_media = media_signature(submission)
      previous_tags = Submitter.applied_tag_names(submission)

      # The submission type never changes on edit: it decides the category,
      # the auto-applied tag and which form is used.
      submission.title = attrs[:title]
      submission.critique_style = attrs[:critique_style]
      submission.data = attrs[:data] || {}

      raise ImagesLocked if locked && media_signature(submission) != original_media

      Submitter.validate!(user, submission)

      ActiveRecord::Base.transaction(requires_new: true) do
        post.lock!

        revisor = PostRevisor.new(post, topic)
        revised =
          revisor.revise!(
            user,
            {
              raw: new_raw(post.raw, submission, keep_project_block: locked),
              title: title_with_revised_marker(topic.title, submission.title),
            },
            skip_validations: true,
          )
        raise Failed, post.errors.full_messages.join(", ") if !revised && post.errors.present?

        apply_tags!(topic, previous_tags, Submitter.applied_tag_names(submission))

        remember_posted_body!(submission, post.reload.raw)
        submission.save!
        submission.submission_uploads.delete_all
        Submitter.persist_uploads(submission)
      end

      # Same as on create: metadata is best-effort and runs outside the
      # transaction. While media is locked the image metadata is left as it
      # was; before any replies, a swapped image becomes the new "original".
      begin
        metadata = TopicMetadata.build(submission)
        metadata = metadata.except(*IMAGE_METADATA_KEYS) if locked
        TopicMetadata.save(topic.reload, metadata)
      rescue => e
        Discourse.warn_exception(
          e,
          message: "[discourse-npn-submissions] metadata save failed on edit topic=#{topic.id}",
        )
      end

      submission
    end

    # --- Loading ---------------------------------------------------------------

    def load!(user, submission_id)
      submission = Submission.submitted.find_by(id: submission_id)
      raise NotFound if submission.blank?
      raise NotEditable if EDITABLE_TYPES.exclude?(submission.submission_type)

      post = first_post(submission)
      raise NotFound if post.blank?
      raise NotAllowed unless editable_by?(user, submission, post: post)

      [submission, post]
    end

    def first_post(submission)
      Post.find_by(topic_id: submission.topic_id, post_number: 1)
    end

    # --- Rules -----------------------------------------------------------------

    # Media locks on critique-style posts once someone else has replied.
    def media_locked?(submission, topic)
      MEDIA_LOCK_TYPES.include?(submission.submission_type) && replied_by_others?(topic)
    end

    # Any visible reply by someone other than the author (system/bot posts and
    # small actions don't count).
    def replied_by_others?(topic)
      Post
        .where(topic_id: topic.id, post_type: Post.types[:regular])
        .where("post_number > 1")
        .where("user_id > 0")
        .where.not(user_id: topic.user_id)
        .exists?
    end

    # What may not change while media is locked. Image notes count for
    # projects (they're captions inside the preserved project block) but not
    # for single images (the note is ordinary post text).
    def media_signature(submission)
      if submission.project?
        {
          method: submission.project_method,
          images: submission.image_entries.map { |e| [e[:upload].id, e[:note]] },
          alternates: submission.alternate_entries.map { |e| [e[:upload].id, e[:note]] },
          pdf: submission.pdf_upload&.id,
          representative: submission.representative_image_upload&.id,
          link: submission.project_link,
        }
      else
        submission.image_entries.map { |entry| entry[:upload].id }
      end
    end

    # True when the post was changed by hand since the form last wrote it.
    #
    # Posts written by this version of the plugin carry a fingerprint of the
    # body. Older posts don't: for those, a post Discourse has never revised
    # can't have been hand-edited, and a revised one is compared with what
    # the form would build now. The comparison can also flag a post only
    # because an older post builder formatted it differently; the user is
    # then asked to confirm, which is the safe outcome.
    def edited_outside_form?(submission, post)
      stored = submission.data[POSTED_BODY_KEY]
      return body_digest(post.raw) != stored if stored.present?
      return false if post.version == 1

      normalize(comparable_body(post.raw)) !=
        normalize(comparable_body(PostBuilder.build(submission)))
    end

    # The part of a post the form owns: the revised-version prefix is dropped
    # and a project block's contents are masked, since the revised-critique
    # plugin rewrites both without going through the form.
    def comparable_body(raw)
      body = body_of(raw)
      inner = project_block_range(body)
      return body if inner.nil?

      body[0...inner.begin] + "\n" + body[inner.end..]
    end

    def body_digest(raw)
      Digest::SHA1.hexdigest(normalize(comparable_body(raw)))
    end

    # Record the fingerprint of the body just written. Called on submit and on
    # every save from the form.
    def remember_posted_body!(submission, raw)
      submission.data = submission.data.merge(POSTED_BODY_KEY => body_digest(raw))
    end

    def normalize(raw)
      TextCleaner.normalize_whitespaces(raw.to_s.gsub("\r\n", "\n")).strip
    end

    # --- Revised-version block -------------------------------------------------

    # The revised-version block plus the "## Original Version" style heading
    # the revised-critique plugin writes after it. Empty when there is none.
    def preserved_prefix(raw)
      raw = raw.to_s
      begin_index = raw.index(REVISED_BEGIN_MARKER)
      end_index = raw.index(REVISED_END_MARKER)
      return "" if begin_index.nil? || end_index.nil? || end_index < begin_index

      cut = end_index + REVISED_END_MARKER.length
      trailing = raw[cut..].match(/\A\s*(?:## [^\n]*\n\s*)?/)
      prefix = raw[0...(cut + trailing[0].length)]
      prefix.end_with?("\n\n") ? prefix : "#{prefix.rstrip}\n\n"
    end

    def body_of(raw)
      raw.to_s.delete_prefix(preserved_prefix(raw))
    end

    # The rebuilt post: the preserved revised-version prefix, then the form's
    # output. With `keep_project_block`, the project block's current contents
    # (which may include rendered project revisions) replace the rebuilt ones.
    def new_raw(current_raw, submission, keep_project_block: false)
      body = PostBuilder.build(submission)
      if keep_project_block
        current = project_block_range(current_raw.to_s)
        rebuilt = project_block_range(body)
        if current && rebuilt
          body = body[0...rebuilt.begin] + current_raw.to_s[current] + body[rebuilt.end..]
        end
      end
      preserved_prefix(current_raw) + body
    end

    # Range of the text between a project post's block markers (exclusive of
    # the markers themselves), or nil.
    def project_block_range(raw)
      begin_index = raw.index(ProjectPostBuilder::PROJECT_BLOCK_BEGIN)
      end_index = raw.index(ProjectPostBuilder::PROJECT_BLOCK_END)
      return nil if begin_index.nil? || end_index.nil? || end_index < begin_index

      (begin_index + ProjectPostBuilder::PROJECT_BLOCK_BEGIN.length)...end_index
    end

    # The revised-critique plugin appends a marker such as "(+revised)" to the
    # topic title. The form only knows the original title, so keep the marker.
    def title_with_revised_marker(current_title, new_title)
      new_title = new_title.to_s.strip
      return new_title unless SiteSetting.respond_to?(:revised_critique_title_marker)

      marker = SiteSetting.revised_critique_title_marker.to_s.strip
      return new_title if marker.blank?
      return new_title if current_title.to_s.exclude?(marker)
      return new_title if new_title.include?(marker)

      candidate = "#{new_title} #{marker}"
      candidate.length <= SiteSetting.max_topic_title_length ? candidate : new_title
    end

    # --- Weekly Challenge ------------------------------------------------------

    # The challenge the post was published under, from the topic metadata
    # written at submit time. Empty Hash when the post had none.
    def weekly_challenge_snapshot(topic)
      fields = topic.custom_fields
      {
        id: fields[TopicMetadata::WP_CHALLENGE_ID_KEY].presence&.to_i,
        title: fields[TopicMetadata::WEEKLY_CHALLENGE_TITLE_KEY].presence,
        dates: fields[TopicMetadata::WEEKLY_CHALLENGE_DATES_KEY].presence,
        url: fields[TopicMetadata::WP_CHALLENGE_URL_KEY].presence,
      }.compact
    end

    # --- Tags --------------------------------------------------------------------

    # Swap the submission's own tags for the new set and leave any tag staff
    # added by hand alone. Applied as the system user, mirroring creation (the
    # author may not be allowed to tag topics directly).
    def apply_tags!(topic, previous, current)
      return if previous.sort == current.sort

      existing = topic.tags.pluck(:name)
      names = ((existing - previous) + current).uniq
      ok = DiscourseTagging.tag_topic_by_names(topic, Guardian.new(Discourse.system_user), names)
      unless ok
        raise Failed, topic.errors.full_messages.join(", ").presence || "Tags could not be updated"
      end
    end
  end
end
