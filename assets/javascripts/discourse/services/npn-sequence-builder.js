import Service, { service } from "@ember/service";
import { i18n } from "discourse-i18n";
import NpnHangSuggesterModal from "../components/modal/npn-hang-suggester-modal";
import NpnHangSuggester from "../components/npn-hang-suggester";
import {
  containsSuggestion,
  findSuggestion,
  parseSuggestion,
  replaceSuggestion,
  suggestionKind,
} from "../lib/npn-hang-suggestion";
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
import { sheetDisplaySize } from "../lib/npn-sequence";
import { createEditSheet } from "../lib/npn-sequence-sheet";

// Entry point for the project-critique tools ("Suggest a hang" — or a
// sequence / selection, depending on the presentation goal — and the "View
// the project" step-through), shared by the plain reply
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
  @service composer;
  @service appEvents;

  // The inline "Suggest a hang" component:
  //   @images @initial @state @onStateChange @onInsert(markup, label) @onCancel
  component = NpnHangSuggester;

  // Suggested-edit tag definitions (key, heading, color, alternateOnly).
  // DEPRECATED: the edit tags now live inside "Suggest a hang"; kept so an
  // older critique workspace keeps working until it's updated.
  editTags = EDIT_TAGS;

  // { kind, label, order, ranks, layout } parsed from a suggestion image in
  // `text` (also older "Suggested sequence" images), or null. Pass the
  // project images so numbers can be checked.
  initialFor(text, images = null) {
    if (!text) {
      return null;
    }
    const all = [...(images?.originals ?? []), ...(images?.alternates ?? [])];
    return parseSuggestion(text, {
      known: all.length ? new Set(all.map((i) => i.number)) : undefined,
      originals: (images?.originals ?? []).map((i) => i.number),
    });
  }

  // "hang" | "sequence" | "selection" — how critics answer this project.
  kindFor(images) {
    return suggestionKind(images?.intent ?? null);
  }

  // Button / modal title for the tool on this project.
  buttonLabelFor(images) {
    return `npn_submissions.suggest.button.${this.kindFor(images)}`;
  }

  containsSuggestion(text) {
    return containsSuggestion(text);
  }

  // The suggestion image with this label already in `text`, or null.
  findSuggestion(text, label) {
    return findSuggestion(text, label);
  }

  // `text` with the suggestion of the same label replaced by `markup`, or
  // null when there's none (insert a new block instead).
  replaceSuggestion(text, label, markup) {
    return replaceSuggestion(text, label, markup);
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

  // ---- Suggest a hang ---------------------------------------------------

  // Puts a suggestion into the open reply composer: replacing one with the
  // same label if the reply already has it, otherwise as its own block.
  insertIntoComposer(markup, label) {
    const model = this.composer.model;
    const replaced = model
      ? replaceSuggestion(model.reply ?? "", label, markup)
      : null;
    if (replaced !== null) {
      model.set("reply", replaced);
    } else {
      this.appEvents.trigger("composer:insert-block", markup);
    }
  }

  // Opens the tool in a modal (the plain reply composer). `selectedText`: if
  // it contains a suggestion image, the tool reopens it for editing (the
  // caller should replace the selection with the returned markup).
  open({ images, selectedText, onInsert }) {
    if (!images?.originals?.length) {
      return;
    }
    const initial = this.initialFor(selectedText, images);
    this.modal.show(NpnHangSuggesterModal, {
      model: {
        images,
        initial,
        title: i18n(this.buttonLabelFor(images)),
        onInsert,
      },
    });
  }
}
