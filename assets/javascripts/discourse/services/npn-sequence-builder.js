import Service, { service } from "@ember/service";
import NpnSequenceBuilderModal from "../components/modal/npn-sequence-builder-modal";
import NpnSequenceBuilder from "../components/npn-sequence-builder";
import { parseSequenceMarkup } from "../lib/npn-sequence";

// Entry point for the Suggest-a-Sequence builder, shared by the plain reply
// composer (this plugin) and the critique workspace
// (discourse-npn-critique-reply). The workspace looks this service up by name
// and only shows its button when the service exists, so neither plugin
// hard-depends on the other.
//
//   const builder = owner.lookup("service:npn-sequence-builder");
//   const images = builder?.imagesFor(topic);
//   if (images) builder.open({ images, selectedText, onInsert(markup) {…} });
//
// Callers that are ALREADY inside a modal (the critique workspace) must not
// call open() — Discourse shows one modal at a time, so it would close them.
// They render `builder.component` inline instead, with `initialFor(text)`.
export default class NpnSequenceBuilderService extends Service {
  @service modal;

  // The inline builder component: @images @initial @onInsert @onCancel.
  component = NpnSequenceBuilder;

  // { label, numbers } parsed from an [npn-sequence] block in `text`, or null.
  initialFor(text) {
    return text ? parseSequenceMarkup(text) : null;
  }

  // The project's numbered images, or null when the topic isn't an
  // image-method project (no builder there).
  imagesFor(topic) {
    const images = topic?.npn_project_images;
    return images?.originals?.length ? images : null;
  }

  // `selectedText`: if it contains an [npn-sequence] block, the builder
  // reopens it for editing (the caller should replace the selection with the
  // returned markup).
  open({ images, selectedText, onInsert }) {
    if (!images?.originals?.length) {
      return;
    }
    const initial = this.initialFor(selectedText);
    this.modal.show(NpnSequenceBuilderModal, {
      model: { images, initial, onInsert },
    });
  }
}
