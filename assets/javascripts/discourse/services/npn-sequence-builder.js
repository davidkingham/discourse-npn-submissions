import Service, { service } from "@ember/service";
import { i18n } from "discourse-i18n";
import NpnHangSuggesterModal from "../components/modal/npn-hang-suggester-modal";
import NpnHangEditor from "../components/npn-hang-editor";
import NpnHangSuggester from "../components/npn-hang-suggester";
import { createHangImage } from "../lib/npn-hang-image";
import {
  containsSuggestion,
  findSuggestionByUpload,
  normalizedLabel,
  parseSuggestion,
  suggestionKind,
  suggestionUpload,
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
import { resolveHang } from "../lib/npn-wall-layout";

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
const INSERTED_STORAGE_KEY = "npn-suggestions-inserted";
const INSERTED_MAX = 60;

function loadInserted() {
  try {
    const saved = JSON.parse(window.localStorage.getItem(INSERTED_STORAGE_KEY));
    return new Map(Array.isArray(saved) ? saved : []);
  } catch {
    return new Map();
  }
}

function saveInserted(map) {
  try {
    window.localStorage.setItem(
      INSERTED_STORAGE_KEY,
      JSON.stringify([...map].slice(-INSERTED_MAX))
    );
  } catch {
    // Private mode / blocked storage: remembered for this page only.
  }
}

export default class NpnSequenceBuilderService extends Service {
  @service modal;
  @service composer;
  @service appEvents;

  // The inline "Suggest a hang" component:
  //   @images @initial @state @onStateChange @onInsert(markup, label) @onCancel
  component = NpnHangSuggester;

  // The hang editor on its own, for other editors of a project's hang (the
  // project revision editor in discourse-npn-revised-critique):
  //   @prints (numbered: { number, upload_id, url, width, height })
  //   @hang @intent @onChange(hang)
  hangEditor = NpnHangEditor;

  // Draws the hang for `prints` as one image and uploads it; resolves to the
  // upload ({ id, short_url, … }). Rejects with error.stage set (see
  // older critique workspace keeps working until it's updated.
  editTags = EDIT_TAGS;

  // name replaces that image (and only that image).
  #inserted = loadInserted();

  // Which of the photographer's proposed orders a reader has on the wall,
  // per project (keyed by its images), as print numbers. The suggest tool
  // starts from it, so "I'd go with your Option B, but…" begins at Option B.
  #viewedOrders = new Map();

  #projectKey(images) {
    return (images?.originals ?? []).map((i) => i.upload_id).join(",");
  }

  noteViewedOrder(images, numbers) {
    this.#viewedOrders.set(this.#projectKey(images), numbers);
  }

  viewedOrderFor(images) {
    return this.#viewedOrders.get(this.#projectKey(images)) ?? null;
  }

  // lib/npn-hang-image.js).
  // `alternates`: more images a book's cover may be chosen from.
  drawHangImage({ prints, hang, intent, alternates = [] }) {
    return createHangImage(
      prints,
      resolveHang(hang, intent, prints, [...prints, ...alternates]),
      { coverLabel: i18n("npn_submissions.book.cover") }
    );
  }

  // Suggested-edit tag definitions (key, heading, color, alternateOnly).
  // DEPRECATED: the edit tags now live inside "Suggest a hang"; kept so an

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

  // Suggestions this critic added (remembered in this browser, so it
  // survives a reload), by topic and
  // name → the upload they were drawn to. Adding one again under the same

  #insertedKey(topicId, label) {
    return `${topicId ?? ""}:${normalizedLabel(label)}`;
  }

  // The image line in `text` that this critic added earlier for this topic
  // under `label`, or null (then insert a new block).
  existingSuggestion(text, topicId, label) {
    return findSuggestionByUpload(
      text,
      this.#inserted.get(this.#insertedKey(topicId, label))
    );
  }

  // Call after inserting or replacing a suggestion.
  noteInserted(topicId, label, markup) {
    const upload = suggestionUpload(markup);
    if (upload) {
      const key = this.#insertedKey(topicId, label);
      // Re-insert so the newest entries are last, and keep a bounded list.
      this.#inserted.delete(key);
      this.#inserted.set(key, upload);
      saveInserted(this.#inserted);
    }
  }

  // The project's numbered images, or null when the topic isn't an
  // image-method project (no tools there).
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

  // Puts a suggestion into the open reply composer: replacing the one this
  // critic added earlier under the same name if it's still in the reply,
  // otherwise as its own block.
  insertIntoComposer(markup, label) {
    const model = this.composer.model;
    const topicId = model?.topic?.id;
    const reply = model?.reply ?? "";
    const existing = model
      ? this.existingSuggestion(reply, topicId, label)
      : null;
    if (existing) {
      model.set(
        "reply",
        reply.replace(existing, () => markup)
      );
    } else {
      this.appEvents.trigger("composer:insert-block", markup);
    }
    this.noteInserted(topicId, label, markup);
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
