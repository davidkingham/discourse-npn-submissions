import DButton from "discourse/ui-kit/d-button";
import NpnLargeImageWarning from "./npn-large-image-warning";
import NpnUploadZone from "./npn-upload-zone";

// One photograph, shown whole on a dark mat, or the place to drop it. The
// single-image forms (New Members Area, Introduction) share this; the
// photo-first critique form builds the same look around NpnImageList, which
// also handles several images. Styled by .npn-photo-form__stage, so the form
// using it carries the .npn-photo-form class.
//
// Args: @image (upload or null), @uploading, @label (drop-zone prompt),
// @onFiles, @onRemove, @optional (a smaller drop zone for a photograph that
// isn't required).
const NpnPhotoStage = <template>
  <div
    class="npn-photo-form__stage
      {{if @image 'has-photo'}}
      {{if @optional 'npn-photo-form__stage--optional'}}"
    ...attributes
  >
    {{#if @image}}
      <div class="npn-image-form__image-row npn-image-form__image-row--single">
        <div class="npn-image-form__thumb">
          <img src={{@image.url}} alt={{@image.original_filename}} />
        </div>
        <DButton
          @icon="trash-can"
          @label="npn_submissions.form.images.remove"
          @action={{@onRemove}}
          class="btn-flat npn-image-form__remove"
        />
        <NpnLargeImageWarning @filesize={{@image.filesize}} />
      </div>
    {{else}}
      <NpnUploadZone
        @accept="image/*"
        @disabled={{@uploading}}
        @label={{@label}}
        @onFiles={{@onFiles}}
      />
    {{/if}}
  </div>
</template>;

export default NpnPhotoStage;
