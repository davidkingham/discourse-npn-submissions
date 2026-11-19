import { apiInitializer } from "discourse/lib/api";
import { iconHTML } from "discourse/lib/icon-library";
import { i18n } from "discourse-i18n";
import { containsSequence } from "../lib/npn-sequence";

// Adds a "Suggest a sequence" button to the composer toolbar when replying on
// an image-method project topic. Selecting an inserted sequence image first
// (in the Markdown editor) and clicking the button reopens it for editing.
export default apiInitializer((api) => {
  // "▶ View the project" above the OP's Project Overview: steps through the
  // images full-screen in order. Only on real posts of image-method projects
  // (the composer preview has no post model, so it's skipped).
  api.decorateCookedElement(
    (element, helper) => {
      const grid = element.querySelector(".npn-project-overview-grid");
      if (
        !grid ||
        grid.previousElementSibling?.classList?.contains("npn-view-project")
      ) {
        return;
      }
      const post = helper?.getModel?.();
      const images = post?.topic?.npn_project_images?.originals;
      if (!images?.length) {
        return;
      }
      const button = document.createElement("button");
      button.type = "button";
      button.className = "btn btn-default btn-small npn-view-project";
      button.innerHTML = `${iconHTML("play")}<span class="d-button-label"></span>`;
      button.querySelector(".d-button-label").textContent = i18n(
        "npn_submissions.project_view.button"
      );
      button.addEventListener("click", () =>
        api.container.lookup("service:npn-sequence-builder").viewProject(images)
      );
      grid.before(button);
    },
    { id: "npn-view-project" }
  );

  const composer = api.container.lookup("service:composer");
  const builder = api.container.lookup("service:npn-sequence-builder");

  const projectImages = () => {
    const model = composer?.model;
    if (!model || model.action !== "reply") {
      return null;
    }
    return builder.imagesFor(model.topic);
  };

  api.onToolbarCreate((toolbar) => {
    toolbar.addButton({
      id: "npn-suggest-sequence",
      group: "extras",
      icon: "film",
      title: "npn_submissions.sequence.toolbar_button",
      preventFocus: true,
      condition: () => !!projectImages(),
      action: (toolbarEvent) => {
        const images = projectImages();
        if (!images) {
          return;
        }
        const selectedText = toolbarEvent.selected?.value;
        const editing = containsSequence(selectedText);
        builder.open({
          images,
          selectedText: editing ? selectedText : null,
          // Replace a selected sequence in place; otherwise insert as its own
          // block. (In the rich editor addText keeps only inline content, so
          // a fresh insert would stick to the previous paragraph/image.)
          onInsert: (markup) =>
            editing
              ? toolbarEvent.addText(markup)
              : api.container
                  .lookup("service:app-events")
                  .trigger("composer:insert-block", markup),
        });
      },
    });
  });
});
