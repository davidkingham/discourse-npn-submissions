import Service, { service } from "@ember/service";
import NpnSequenceBuilderModal from "../components/modal/npn-sequence-builder-modal";
import NpnSequenceBuilder from "../components/npn-sequence-builder";
import {
  buildEditMarkup,
  EDIT_TAGS,
  editGroups,
  editSummary,
  hasEditTags,
  replaceEditImage,
  tagsFor,
} from "../lib/npn-project-edit";
import { openProjectViewer } from "../lib/npn-project-viewer";
import { parseSequenceMarkup, sheetDisplaySize } from "../lib/npn-sequence";
import { createEditSheet } from "../lib/npn-sequence-sheet";

// Entry point for the project-critique tools (Suggest-a-Sequence builder,
// "View the project" step-through, suggested-edit sheet), shared by the plain reply
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

  // Suggested-edit tag definitions (key, heading, color, alternateOnly).
  editTags = EDIT_TAGS;

  // { label, numbers } parsed from a suggested-sequence image in `text`, or
  // null.
  initialFor(text) {
    return text ? parseSequenceMarkup(text) : null;
  }

  // The project's numbered images, or null when the topic isn't an
  // image-method project (no builder there).
  imagesFor(topic) {
    const images = topic?.npn_project_images;
    return images?.originals?.length ? images : null;
  }

  // ---- View the project ---------------------------------------------------

  // Step through `images` (default: the originals) full-screen, in order.
  viewProject(images, startIndex = 0) {
    return openProjectViewer(images, startIndex);
  }

  // ---- Suggested edit (keep / cut) ---------------------------------------

  tagsFor(number) {
    return tagsFor(number);
  }

  hasEditTags(tags) {
    return hasEditTags(tags);
  }

  // Draws and uploads the grouped edit sheet for `tags`
  // ({ "4": "strongest", … }) and resolves to the image markdown. Rejects if
  // nothing is tagged or the sheet can't be made.
  async buildEditImage({ images, tags }) {
    const all = [...(images?.originals ?? []), ...(images?.alternates ?? [])];
    const groups = editGroups(tags, all);
    if (!groups.length) {
      throw new Error("project edit: nothing tagged");
    }
    const sheet = await createEditSheet({ groups });
    return buildEditMarkup({
      groups,
      image: {
        short_url: sheet.upload.short_url,
        ...sheetDisplaySize(sheet.width, sheet.height),
      },
    });
  }

  // The alt-text summary ("strongest 4; keep 1, 3; cut 9") the edit image
  // for these tags would carry — lets a caller tell whether an edit image
  // already in the text is up to date.
  editSummaryFor({ images, tags }) {
    const all = [...(images?.originals ?? []), ...(images?.alternates ?? [])];
    return editSummary(editGroups(tags, all));
  }

  // Replaces an existing suggested-edit image in `text`; null if none.
  replaceEditImage(text, markup) {
    return replaceEditImage(text, markup);
  }

  // ---- Suggest a sequence --------------------------------------------------

  // `selectedText`: if it contains a suggested-sequence image, the builder
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
