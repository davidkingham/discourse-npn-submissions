import { i18n } from "discourse-i18n";

// Read-only images for a post being edited after others have replied:
// critiques refer to these images, so a new one goes through "Share a Revised
// Version" instead. @images: [{ url, original_filename, note? }].
// @noticeKey overrides the explanation (e.g. for projects).
const NpnLockedImages = <template>
  <p class="npn-image-form__notice npn-image-form__notice--info">
    {{i18n
      (if @noticeKey @noticeKey "npn_submissions.form.edit.images_locked")
    }}
  </p>
  {{#if @images.length}}
    <ul class="npn-image-form__locked-images">
      {{#each @images as |image|}}
        <li class="npn-image-form__locked-image">
          <img
            src={{image.url}}
            alt={{image.original_filename}}
            loading="lazy"
          />
          {{#if image.note}}
            <p class="npn-help">{{image.note}}</p>
          {{/if}}
        </li>
      {{/each}}
    </ul>
  {{/if}}
</template>;

export default NpnLockedImages;
