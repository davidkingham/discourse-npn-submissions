# frozen_string_literal: true

module DiscourseNpnSubmissions
  # Turns a draft (or inline submission attributes) into a real Discourse topic.
  #
  # The plugin is the authorization boundary here: we run our own Policy,
  # validation and DailyLimit checks and then call PostCreator with
  # skip_guardian + skip_validations so the managed-category lock and trust-level
  # content rules do not block our controlled path. The topic is still owned by
  # the submitting user. Because Discourse's own content validation is skipped,
  # the validation in this service is what keeps obviously-bad topics out.
  module Submitter
    class NotAllowed < StandardError
    end

    class InvalidType < StandardError
    end

    class CreationFailed < StandardError
    end

    class InvalidSubmission < StandardError
    end

    module_function

    # Returns the submission record (status "submitted") on success. Raises
    # NotAllowed / InvalidType / InvalidSubmission / DailyLimit::Exceeded /
    # CreationFailed. On the non-creation failures the draft is left untouched.
    def call(user:, draft_id: nil, attrs: {}, tz_name: nil)
      raise NotAllowed unless Policy.can_submit?(user)

      submission = resolve_submission(user, draft_id, attrs, tz_name)

      raise InvalidType if Submission::SUBMISSION_TYPES.exclude?(submission.submission_type)

      validate!(user, submission)

      # Daily limit is checked BEFORE topic creation. If it raises, the draft is
      # left untouched (status stays "draft") so the user keeps their work.
      # Only critique submission types count toward the daily limit — the
      # purpose of the limit is to keep critique threads from being flooded by
      # one person, and onboarding submissions (Introduction, New Members Area
      # image) don't belong to that category. Using the enum directly so any
      # future non-critique type is automatically exempt without a new branch.
      if Submission::CRITIQUE_SUBMISSION_TYPES.include?(submission.submission_type)
        DailyLimit.check!(user: user, tz_name: tz_name || submission.client_timezone)
      end

      create_topic!(user, submission, tz_name)
      submission
    end

    # Builds the post for an in-memory submission so the client can show a
    # preview. Runs the same authorization, type and content validation as #call,
    # but never persists a draft, creates uploads/topics, or enforces the daily
    # limit. Works for any submission type the post builder supports. Returns
    # { markdown:, tags: } (tags are the descriptive tags that will be applied,
    # including the auto-added Weekly Challenge tag); raises the same errors as
    # #call.
    def preview(user:, attrs: {}, tz_name: nil)
      raise NotAllowed unless Policy.can_submit?(user)

      submission = build_preview_submission(user, attrs, tz_name)

      raise InvalidType if Submission::SUBMISSION_TYPES.exclude?(submission.submission_type)

      validate!(user, submission)
      { markdown: PostBuilder.build(submission), tags: applied_tag_names(submission) }
    end

    def resolve_submission(user, draft_id, attrs, tz_name)
      if draft_id.present?
        # Submit reflects the current form. Fold the submitted attrs into the
        # existing draft before validating; otherwise edits made since the last
        # "Save draft" (e.g. a newly added image) are silently dropped and the
        # stale, possibly image-less, stored draft is submitted instead.
        if attrs.present?
          DraftStore.update(user, draft_id, attrs.merge(client_timezone: tz_name))
        else
          DraftStore.find(user, draft_id)
        end
      else
        DraftStore.create(user, attrs.merge(client_timezone: tz_name))
      end
    end

    # An unsaved Submission mirroring the submitted form, used only to build a
    # preview. Never written to the database.
    def build_preview_submission(user, attrs, tz_name)
      Submission.new(
        user: user,
        status: "draft",
        submission_type: attrs[:submission_type],
        critique_style: attrs[:critique_style],
        title: attrs[:title],
        data: attrs[:data] || {},
        client_timezone: tz_name,
      )
    end

    # --- Validation boundary ---------------------------------------------------
    # Runs before PostCreator. Raises InvalidSubmission with a user-facing
    # message; the draft is left intact so the user can fix and retry.

    def validate!(user, submission)
      validate_title!(submission)
      validate_category!(submission)
      # validate_tags! is safe to call for every type: it's a no-op for
      # submissions that aren't in TAG_REQUIRED_TYPES and have no user-supplied
      # tags. Introductions take that path (no tag chooser, no tag data).
      validate_tags!(submission)

      if submission.project?
        validate_project!(submission)
      elsif submission.introduction?
        validate_introduction!(submission)
      elsif submission.new_member_image?
        validate_new_member_image!(submission)
      elsif submission.help?
        validate_help!(submission)
      else
        validate_critique_style!(submission)
        validate_feedback_focus!(submission)
        validate_image_count!(submission)
        validate_required_fields!(submission)
      end

      validate_upload_ownership!(user, submission)
      validate_body!(submission)
    end

    # Introductions are intentionally light: a non-empty "About You" body, an
    # optional learning/exploration body, and at most one optional image. The
    # title is already enforced by validate_title!.
    def validate_introduction!(submission)
      raise InvalidSubmission, "About You is required." if submission.field("about").blank?

      count = submission.image_entries.size
      raise InvalidSubmission, "You can include at most one image in an introduction." if count > 1
    end

    # New Members Area image submissions require exactly one image and a
    # title. "About This Image" and "Feedback Welcome" are both optional;
    # this stays a low-pressure onboarding post.
    def validate_new_member_image!(submission)
      count = submission.image_entries.size
      if count.zero?
        raise InvalidSubmission, "An image is required."
      elsif count > 1
        raise InvalidSubmission, "You can include only one image for this submission."
      end
    end

    # Help submissions need only a non-empty description; screenshots
    # (0–3) and the diagnostic info are both optional. Title is enforced
    # by validate_title!.
    MAX_HELP_SCREENSHOTS = 3
    def validate_help!(submission)
      if submission.field("description").blank?
        raise InvalidSubmission, "Please describe what's happening."
      end

      count = submission.image_entries.size
      if count > MAX_HELP_SCREENSHOTS
        raise InvalidSubmission, "You can include up to #{MAX_HELP_SCREENSHOTS} screenshots."
      end
    end

    def validate_title!(submission)
      title = submission.title.to_s.strip
      raise InvalidSubmission, "Title is required." if title.blank?

      min = SiteSetting.min_topic_title_length
      max = SiteSetting.max_topic_title_length
      if title.length < min
        raise InvalidSubmission, "Title is too short (minimum is #{min} characters)."
      elsif title.length > max
        raise InvalidSubmission, "Title is too long (maximum is #{max} characters)."
      end
    end

    def validate_critique_style!(submission)
      return if Submission::CRITIQUE_STYLE_REQUIRED_TYPES.exclude?(submission.submission_type)

      if Submission::CRITIQUE_STYLES.exclude?(submission.critique_style)
        raise InvalidSubmission, "A critique style is required."
      end
    end

    def validate_feedback_focus!(submission)
      return if Submission::CRITIQUE_STYLE_REQUIRED_TYPES.exclude?(submission.submission_type)

      if Submission::FEEDBACK_FOCUSES.exclude?(submission.feedback_focus)
        raise InvalidSubmission, "Please choose what kind of feedback would be most helpful."
      end
    end

    # Per-style required fields, plus Technical Details when the focus is technical.
    def validate_required_fields!(submission)
      required = Submission::REQUIRED_FIELDS_BY_STYLE[submission.critique_style] || []
      required.each do |key|
        if submission.field(key).blank?
          raise InvalidSubmission, "#{PostBuilder::HEADINGS[key] || key} is required."
        end
      end

      if submission.feedback_focus == "technical" && submission.field("technical_details").blank? &&
           submission.metadata_screenshot_upload.blank?
        raise InvalidSubmission,
              "Technical Details is required when you ask for technical help. Add the details or upload a metadata screenshot."
      end
    end

    def validate_category!(submission)
      id = target_category_id(submission)
      if id.blank?
        raise InvalidSubmission, "No target category is configured for this submission type."
      end
      unless Category.exists?(id: id)
        raise InvalidSubmission, "The configured target category does not exist."
      end
    end

    def validate_image_count!(submission)
      return if Submission::UPLOAD_REQUIRED_TYPES.exclude?(submission.submission_type)

      count = submission.image_entries.size
      raise InvalidSubmission, "At least one image is required." if count.zero?

      max = max_images(submission)
      if max.positive? && count > max
        raise InvalidSubmission, "You can upload at most #{max} #{max == 1 ? "image" : "images"}."
      end
    end

    # Every referenced upload must be one this user can legitimately use. The
    # check below mirrors Discourse's own `UserGuardian#can_pick_avatar?`: staff
    # may use any upload, otherwise either the upload is owned by the user OR a
    # UserUpload join row exists. The join row is the authoritative "this user
    # pushed these bytes through /uploads.json" signal — Discourse creates it
    # even on the SHA1-dedup path, where a re-upload returns an *existing*
    # Upload record (with the original uploader's user_id, not the current
    # user's). Without that, any user uploading content that happens to match an
    # existing sha1 fails the guard, with no obvious cause.
    def validate_upload_ownership!(user, submission)
      inaccessible =
        submission.referenced_uploads.reject { |upload| upload_accessible?(user, upload) }
      return if inaccessible.empty?

      Rails.logger.warn(
        "[discourse-npn-submissions] upload ownership check failed " \
          "user_id=#{user.id} uploads=" +
          inaccessible.map { |u| { id: u.id, owner: u.user_id } }.inspect,
      )
      raise InvalidSubmission, "One or more uploads are not available to you."
    end

    # --- Project validation ----------------------------------------------------

    def validate_project!(submission)
      validate_project_method!(submission)
      validate_project_focus!(submission)
      validate_project_media!(submission)
      validate_project_fields!(submission)
    end

    def validate_project_method!(submission)
      if Submission::PROJECT_METHODS.exclude?(submission.project_method)
        raise InvalidSubmission, "Please choose how you'd like to submit your project."
      end
    end

    def validate_project_focus!(submission)
      if Submission::FEEDBACK_FOCUSES.exclude?(submission.feedback_focus)
        raise InvalidSubmission, "Please choose what kind of feedback would be most helpful."
      end
    end

    # The 6-image recommendation is a soft, frontend-only warning; the server
    # only enforces at-least-one and the maximum.
    def validate_project_media!(submission)
      case submission.project_method
      when "images"
        count = submission.image_entries.size
        raise InvalidSubmission, "Add at least one project image." if count.zero?

        max = max_images(submission)
        if max.positive? && count > max
          raise InvalidSubmission, "You can upload at most #{max} project images."
        end
      when "pdf"
        if submission.pdf_upload.blank?
          raise InvalidSubmission, "A PDF is required for this submission method."
        end
        validate_representative_image!(submission)
      when "url"
        unless valid_url?(submission.project_link)
          raise InvalidSubmission, "A valid project URL is required."
        end
        validate_representative_image!(submission)
      end
    end

    # PDF and URL projects need an image so the topic has a thumbnail in topic
    # lists. Uploaded-image projects use their first image instead.
    def validate_representative_image!(submission)
      upload = submission.representative_image_upload
      raise InvalidSubmission, "A representative image is required." if upload.blank?

      unless FileHelper.is_supported_image?(upload.original_filename)
        raise InvalidSubmission, "The representative image must be an image file."
      end
    end

    def validate_project_fields!(submission)
      labels = ProjectPostBuilder::HEADINGS.merge("project_intent" => "Presentation Goal")
      Submission::PROJECT_REQUIRED_FIELDS.each do |key|
        if submission.field(key).blank?
          raise InvalidSubmission, "#{labels[key] || key} is required."
        end
      end

      intent = submission.field("project_intent")
      if intent.present? && Submission::PROJECT_INTENTS.exclude?(intent)
        raise InvalidSubmission, "Please choose a valid project intent."
      end
    end

    def valid_url?(url)
      url = url.to_s.strip
      return false if url.blank?

      uri = URI.parse(url)
      uri.is_a?(URI::HTTP) && uri.host.present?
    rescue URI::InvalidURIError
      false
    end

    def max_images(submission)
      case submission.submission_type
      when "project"
        SiteSetting.npn_submissions_max_project_images.to_i
      else
        SiteSetting.npn_submissions_max_single_images.to_i
      end
    end

    # At least one user-selected descriptive tag is required for critique
    # submissions, and every applied tag (the user's tags plus the auto-added
    # Weekly Challenge tag) must already exist; this path never creates tags.
    def validate_tags!(submission)
      user_tags = submission.descriptive_tag_names

      if user_tags.empty? && Submission::TAG_REQUIRED_TYPES.include?(submission.submission_type)
        raise InvalidSubmission, "At least one descriptive tag is required."
      end

      # When a descriptive tag group is configured, the user's chosen tags must
      # all belong to it. The auto-applied weekly tag is exempt (checked below).
      if Policy.descriptive_tags_constrained?
        outside = user_tags - Policy.allowed_descriptive_tag_names
        if outside.present?
          raise InvalidSubmission, "These tags aren't allowed here: #{outside.join(", ")}."
        end
      end

      applied = applied_tag_names(submission)
      return if applied.empty?

      missing = applied - Tag.where(name: applied).pluck(:name)
      raise InvalidSubmission, "Unknown tags: #{missing.join(", ")}." if missing.present?
    end

    # The descriptive tags applied to the created topic: the user's chosen tags
    # plus the auto-applied tag for the submission type (Weekly Challenge tag for
    # weekly_challenge, Project tag for project). Deduped, and never invents
    # anything beyond the admin-configured auto tag.
    def applied_tag_names(submission)
      names = submission.descriptive_tag_names
      auto = auto_applied_tag(submission)
      names = (names + [auto]).reject(&:blank?).uniq if auto.present?
      names
    end

    def auto_applied_tag(submission)
      case submission.submission_type
      when "weekly_challenge"
        SiteSetting.npn_submissions_weekly_challenge_tag.to_s.strip
      when "project"
        SiteSetting.npn_submissions_project_tag.to_s.strip
      end
    end

    def validate_body!(submission)
      raise InvalidSubmission, "Submission has no content." if PostBuilder.build(submission).blank?
    end

    def upload_accessible?(user, upload)
      return true if user.staff?
      return true if upload.user_id == user.id
      # Dedup case: the upload itself is owned by an earlier uploader, but a
      # UserUpload row was added when this user re-uploaded the same bytes.
      UserUpload.exists?(upload_id: upload.id, user_id: user.id)
    end

    # --- Topic creation --------------------------------------------------------

    def create_topic!(user, submission, tz_name)
      post = nil
      failure = nil
      already_submitted = false

      begin
        # PostCreator, upload persistence and the final status flip all run in one
        # transaction so they commit together. If upload persistence or the status
        # update raises after the post is created, the topic is rolled back too —
        # we never leave a created topic while the submission is still a draft
        # (which would let the user submit a duplicate). `requires_new: true` makes
        # this a real transaction/savepoint in production and a savepoint under the
        # test/request transaction, so the rollback always takes effect.
        ActiveRecord::Base.transaction(requires_new: true) do
          # Serialize concurrent submits of the same draft. A second request
          # that raced past the initial "draft" read blocks on this row lock
          # until the first commits, then sees "submitted" and bails — without
          # creating a duplicate topic or overwriting the successful record with
          # a spurious "failed" status (the upload unique-index collision the
          # loser would otherwise hit).
          submission.lock!
          if submission.status == "submitted" && submission.topic_id.present?
            already_submitted = true
            raise ActiveRecord::Rollback
          end

          creator =
            PostCreator.new(
              user,
              title: submission.title,
              raw: PostBuilder.build(submission),
              category: target_category_id(submission),
              tags: applied_tag_names(submission),
              skip_guardian: true,
              skip_validations: true,
            )

          post = creator.create

          if post.blank? || creator.errors.present?
            failure = creator.errors.full_messages.join(", ").presence || "Topic creation failed"
            raise ActiveRecord::Rollback
          end

          persist_uploads(submission)

          submission.update!(
            status: "submitted",
            topic_id: post.topic_id,
            submitted_at: Time.zone.now,
            client_timezone: tz_name || submission.client_timezone,
            error_message: nil,
          )
        end
      rescue => e
        # Unexpected error during upload persistence or the status update; the
        # transaction has rolled the topic back. Fall through to mark failed.
        failure = e.message
      end

      # A concurrent request already committed this submission. `submission`
      # reflects the locked "submitted" row read above; return without touching
      # it or running the metadata save (which would deref a nil post).
      return if already_submitted

      if failure
        # Written as a separate statement so it survives the rolled-back
        # transaction and surfaces in the admin troubleshooting dashboard.
        # `reload` discards any stale in-memory attributes from the rolled-back
        # update so we don't persist a topic_id for a topic that no longer exists.
        submission.reload
        submission.update!(
          status: "failed",
          error_message: failure,
          client_timezone: tz_name || submission.client_timezone,
        )
        raise CreationFailed, failure
      end

      # Attach the small, durable metadata bag to the topic for future plugins
      # (critique tools, Weekly Challenge filter) to read. Runs OUTSIDE the
      # transaction so a metadata-save failure can never roll the topic back.
      # TopicMetadata.save has its own rescue; this outer rescue is
      # belt-and-suspenders — under no circumstance should a metadata failure
      # surface as a submission failure to the user.
      begin
        TopicMetadata.save(post.topic, TopicMetadata.build(submission))
      rescue => e
        Discourse.warn_exception(
          e,
          message: "[discourse-npn-submissions] metadata save failed for topic=#{post.topic_id}",
        )
      end
    end

    def target_category_id(submission)
      raw =
        case submission.submission_type
        when "image", "weekly_challenge"
          SiteSetting.npn_submissions_critique_category_id
        when "project"
          SiteSetting.npn_submissions_project_category_id
        when "introduction"
          SiteSetting.npn_submissions_introduction_category_id
        when "new_member_image"
          SiteSetting.npn_submissions_new_member_image_category_id
        when "help"
          SiteSetting.npn_submissions_help_category_id
        end
      raw.presence&.to_i
    end

    def persist_uploads(submission)
      if submission.project?
        persist_project_uploads(submission)
      else
        persist_image_uploads(submission)
      end
    end

    def persist_image_uploads(submission)
      main = submission.main_upload
      if main
        DiscourseNpnSubmissions::SubmissionUpload.create!(
          submission_id: submission.id,
          upload_id: main.id,
          role: "main",
          position: 0,
        )
      end

      submission.additional_image_entries.each_with_index do |entry, index|
        DiscourseNpnSubmissions::SubmissionUpload.create!(
          submission_id: submission.id,
          upload_id: entry[:upload].id,
          role: "variation",
          position: index + 1,
          caption: entry[:note].presence,
        )
      end

      if (screenshot = submission.metadata_screenshot_upload)
        DiscourseNpnSubmissions::SubmissionUpload.create!(
          submission_id: submission.id,
          upload_id: screenshot.id,
          role: "metadata_screenshot",
          position: submission.image_entries.size,
        )
      end
    end

    # Project uploads keep their order via position. Roles: project_image,
    # alternate, pdf.
    def persist_project_uploads(submission)
      submission.image_entries.each_with_index do |entry, index|
        DiscourseNpnSubmissions::SubmissionUpload.create!(
          submission_id: submission.id,
          upload_id: entry[:upload].id,
          role: "project_image",
          position: index,
        )
      end

      submission.alternate_entries.each_with_index do |entry, index|
        DiscourseNpnSubmissions::SubmissionUpload.create!(
          submission_id: submission.id,
          upload_id: entry[:upload].id,
          role: "alternate",
          position: index,
        )
      end

      if (pdf = submission.pdf_upload)
        DiscourseNpnSubmissions::SubmissionUpload.create!(
          submission_id: submission.id,
          upload_id: pdf.id,
          role: "pdf",
          position: 0,
        )
      end

      if (rep = submission.representative_image_upload)
        DiscourseNpnSubmissions::SubmissionUpload.create!(
          submission_id: submission.id,
          upload_id: rep.id,
          role: "representative_image",
          position: 0,
        )
      end
    end
  end
end
