import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { schedule } from "@ember/runloop";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import getURL from "discourse/lib/get-url";
import { optionalRequire } from "discourse/lib/utilities";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import NpnField from "./npn-field";
import NpnUploadZone from "./npn-upload-zone";

// Profile setup form — a native port of the old "Fill Out Your Profile" Custom
// Wizard. All fields are optional. It writes straight to the user's core
// profile via Discourse's own endpoints (no plugin backend):
//   - avatar: POST /uploads.json (upload_type=avatar) then user.pickAvatar(id, "custom")
//   - bio / website: user.save([...]) → PUT /u/:username
//   - location: geo_location user custom field → PUT /u/:username
//
// The location field is an OPTIONAL integration with discourse-npn-locations:
// its LocationSelector is resolved lazily via optionalRequire so the submissions
// plugin never hard-fails to load when that plugin is absent or disabled. The
// field only renders when both the module resolves and location_enabled is on.
//
// The user model is loaded with full details by routes/setup.js, so existing
// values are prefilled and this reads as "edit my profile", not a blank wizard.
export default class NpnSetupForm extends Component {
  @service siteSettings;
  @service toasts;

  @tracked website;
  // Geocoded location object ({ address, lat, lon, ... }) or null. Persisted as
  // the `geo_location` user custom field owned by discourse-npn-locations.
  @tracked geoLocation = null;
  @tracked bio;
  // Preview URL for a freshly uploaded avatar; null until one is chosen.
  @tracked newAvatarUrl = null;
  @tracked avatarUploadId = null;
  @tracked uploading = false;
  @tracked saving = false;

  constructor() {
    super(...arguments);
    const user = this.args.user;
    this.website = user?.website || "";
    // The user serializer (from discourse-npn-locations) returns geo_location
    // already parsed into an object, or null.
    this.geoLocation = user?.geo_location || null;
    this.bio = user?.bio_raw || "";

    // NpnField's textarea is uncontrolled; seed it once after render.
    if (this.bio) {
      schedule("afterRender", this, () => {
        const el = document.getElementById("npn-field-bio");
        if (el) {
          el.value = this.bio;
        }
      });
    }
  }

  // Avatar uploads are pointless if the site forces avatars from an external
  // source — hide the field rather than letting pick_avatar 422.
  get avatarEditable() {
    return !(
      this.siteSettings?.discourse_connect_overrides_avatar ||
      this.siteSettings?.auth_overrides_avatar
    );
  }

  get avatarPreviewUrl() {
    if (this.newAvatarUrl) {
      return this.newAvatarUrl;
    }
    const template = this.args.user?.avatar_template;
    if (template) {
      return getURL(template.replace("{size}", "120"));
    }
    return null;
  }

  get busy() {
    return this.uploading || this.saving;
  }

  @action
  updateWebsite(event) {
    this.website = event.target.value;
  }

  // The LocationSelector component from discourse-npn-locations, or undefined if
  // that plugin isn't loaded. Resolved via the loader (not a static import) so a
  // missing plugin can't break this module.
  get locationSelector() {
    return optionalRequire(
      "discourse/plugins/discourse-npn-locations/discourse/components/location-selector"
    );
  }

  // True only when the locations plugin is loaded AND enabled. If it is missing,
  // or installed but disabled, hide the field rather than render a selector
  // backed by an unavailable /locations/search endpoint.
  get locationEnabled() {
    return !!(this.siteSettings?.location_enabled && this.locationSelector);
  }

  // LocationSelector emits the full geo object on pick, or undefined/{} on clear.
  @action
  onLocationChange(location) {
    if (
      !location ||
      (typeof location === "object" && Object.keys(location).length === 0)
    ) {
      this.geoLocation = null;
    } else {
      this.geoLocation = location;
    }
  }

  @action
  updateBio(event) {
    this.bio = event.target.value;
  }

  // --- Avatar ---------------------------------------------------------------

  @action
  async addAvatarFiles(files) {
    const file = files[0];
    if (!file) {
      return;
    }
    const formData = new FormData();
    formData.append("upload_type", "avatar");
    formData.append("file", file);
    this.uploading = true;
    try {
      const upload = await ajax("/uploads.json", {
        type: "POST",
        data: formData,
        processData: false,
        contentType: false,
      });
      if (upload) {
        this.avatarUploadId = upload.id;
        this.newAvatarUrl = upload.url;
      }
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.uploading = false;
    }
  }

  @action
  removeAvatar() {
    this.avatarUploadId = null;
    this.newAvatarUrl = null;
  }

  // --- Save -----------------------------------------------------------------

  @action
  async save(event) {
    event?.preventDefault();
    this.saving = true;
    try {
      const user = this.args.user;

      // Avatar first so a failure here doesn't leave the profile half-saved
      // with no clear cause. pickAvatar only returns success; the live header
      // avatar refreshes on the next navigation/reload, while the in-form
      // preview already shows the chosen photo.
      if (this.avatarUploadId) {
        await user.pickAvatar(this.avatarUploadId, "custom");
        this.avatarUploadId = null;
      }

      user.setProperties({
        bio_raw: this.bio,
        website: this.website,
      });

      // Persist the geocoded location as the `geo_location` user custom field,
      // mirroring discourse-npn-locations: a JSON string when set, "" to clear.
      // The locations plugin's server modifier validates and stores it; we just
      // send custom_fields through core's PUT /u/:username.
      if (this.locationEnabled) {
        if (!user.custom_fields) {
          user.set("custom_fields", {});
        }
        user.set(
          "custom_fields.geo_location",
          this.geoLocation ? JSON.stringify(this.geoLocation) : ""
        );
        await user.save(["bio_raw", "website", "custom_fields"]);
      } else {
        await user.save(["bio_raw", "website"]);
      }

      this.toasts.success({
        duration: "short",
        data: { message: i18n("npn_submissions.setup.saved") },
      });
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.saving = false;
    }
  }

  <template>
    <form class="npn-image-form npn-setup-form" {{on "submit" this.save}}>
      <header class="npn-image-form__intro">
        <h2>{{i18n "npn_submissions.setup.intro.title"}}</h2>
        <p class="npn-image-form__lead">
          {{i18n "npn_submissions.setup.intro.lead"}}
        </p>
      </header>

      {{! Avatar — optional }}
      {{#if this.avatarEditable}}
        <div class="npn-image-form__field npn-setup-form__avatar-field">
          <label>
            {{i18n "npn_submissions.setup.fields.avatar.label"}}
            <span class="npn-optional">{{i18n
                "npn_submissions.form.optional"
              }}</span>
          </label>
          <p class="npn-help">{{i18n
              "npn_submissions.setup.fields.avatar.help"
            }}</p>

          {{#if this.avatarPreviewUrl}}
            <div class="npn-image-form__image-row">
              <div class="npn-image-form__thumb npn-setup-form__avatar-thumb">
                <img src={{this.avatarPreviewUrl}} alt="" />
              </div>
              {{#if this.newAvatarUrl}}
                <DButton
                  @icon="trash-can"
                  @action={{this.removeAvatar}}
                  @title="npn_submissions.form.images.remove"
                  @ariaLabel="npn_submissions.form.images.remove"
                  class="btn-flat"
                />
              {{/if}}
            </div>
          {{/if}}

          <NpnUploadZone
            @accept="image/*"
            @disabled={{this.uploading}}
            @label={{i18n "npn_submissions.setup.fields.avatar.upload_label"}}
            @onFiles={{this.addAvatarFiles}}
          />
        </div>
      {{/if}}

      {{! Website — optional }}
      <div class="npn-image-form__field">
        <label for="npn-setup-website">
          {{i18n "npn_submissions.setup.fields.website.label"}}
          <span class="npn-optional">{{i18n
              "npn_submissions.form.optional"
            }}</span>
        </label>
        <p class="npn-help">{{i18n
            "npn_submissions.setup.fields.website.help"
          }}</p>
        <input
          id="npn-setup-website"
          type="text"
          value={{this.website}}
          {{on "input" this.updateWebsite}}
        />
      </div>

      {{! Location — optional, geocoded via discourse-npn-locations }}
      {{#if this.locationEnabled}}
        <div class="npn-image-form__field npn-setup-form__location-field">
          <label>
            {{i18n "npn_submissions.setup.fields.location.label"}}
            <span class="npn-optional">{{i18n
                "npn_submissions.form.optional"
              }}</span>
          </label>
          <p class="npn-help">{{i18n
              "npn_submissions.setup.fields.location.help"
            }}</p>
          <this.locationSelector
            @location={{this.geoLocation}}
            @onChangeCallback={{this.onLocationChange}}
            @showType={{false}}
            @placeholder={{i18n
              "npn_submissions.setup.fields.location.placeholder"
            }}
          />
        </div>
      {{/if}}

      {{! Bio — optional }}
      <NpnField
        @fieldId="npn-field-bio"
        @label={{i18n "npn_submissions.setup.fields.bio.label"}}
        @help={{i18n "npn_submissions.setup.fields.bio.help"}}
        @optional={{true}}
        @onInput={{this.updateBio}}
      />

      <div class="npn-image-form__actions">
        <DButton
          @label="npn_submissions.setup.save"
          @action={{this.save}}
          @disabled={{this.busy}}
          @isLoading={{this.saving}}
          class="btn-primary"
        />
      </div>
    </form>
  </template>
}
