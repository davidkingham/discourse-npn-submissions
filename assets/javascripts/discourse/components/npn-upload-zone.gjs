import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import dIcon from "discourse/ui-kit/helpers/d-icon";

// A modern upload control: click (or keyboard) to browse, or drag files from the
// desktop onto the zone. Emits the chosen files as an array via @onFiles.
//
// It only reacts to real file drags (dataTransfer contains "Files"), so dragging
// an existing image row to reorder it never activates the zone.
//
// Args: @onFiles (required), @label, @accept, @multiple, @disabled.
export default class NpnUploadZone extends Component {
  @tracked dragging = false;

  get multiple() {
    return this.args.multiple ?? false;
  }

  hasFiles(event) {
    return Array.from(event.dataTransfer?.types || []).includes("Files");
  }

  emit(fileList) {
    const files = Array.from(fileList || []);
    if (files.length) {
      this.args.onFiles?.(files);
    }
  }

  @action
  filesChosen(event) {
    // Copy to a real array BEFORE clearing the input: event.target.files is a
    // live FileList, so resetting value (to allow re-picking the same file)
    // would empty it before emit reads it.
    const files = Array.from(event.target.files || []);
    event.target.value = null;
    this.emit(files);
  }

  @action
  dragOver(event) {
    if (this.args.disabled || !this.hasFiles(event)) {
      return;
    }
    event.preventDefault();
    event.dataTransfer.dropEffect = "copy";
    this.dragging = true;
  }

  @action
  dragLeave(event) {
    // Ignore dragleave bubbling up from child elements; only clear when the
    // pointer actually leaves the zone.
    if (!event.currentTarget.contains(event.relatedTarget)) {
      this.dragging = false;
    }
  }

  @action
  drop(event) {
    if (this.args.disabled || !this.hasFiles(event)) {
      return;
    }
    event.preventDefault();
    this.dragging = false;
    this.emit(event.dataTransfer.files);
  }

  <template>
    <label
      class="npn-upload-zone
        {{if this.dragging 'is-dragging'}}
        {{if @disabled 'is-disabled'}}"
      {{on "dragenter" this.dragOver}}
      {{on "dragover" this.dragOver}}
      {{on "dragleave" this.dragLeave}}
      {{on "drop" this.drop}}
    >
      {{dIcon "cloud-arrow-up"}}
      <span class="npn-upload-zone__label">{{@label}}</span>
      <input
        type="file"
        accept={{@accept}}
        multiple={{this.multiple}}
        disabled={{@disabled}}
        {{on "change" this.filesChosen}}
      />
    </label>
  </template>
}
