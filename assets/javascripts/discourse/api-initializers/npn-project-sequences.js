import { apiInitializer } from "discourse/lib/api";
import NpnExhibitionWall from "../components/npn-exhibition-wall";
import { containsSequence } from "../lib/npn-sequence";

// Adds a "Suggest a sequence" button to the composer toolbar when replying on
// an image-method project topic. Selecting an inserted sequence image first
// (in the Markdown editor) and clicking the button reopens it for editing.
export default apiInitializer((api) => {
  // The exhibition wall on the OP of a project topic: the whole project hung
  // on a gallery wall (framed, matted, true proportions), replacing the
  // Project Overview contact sheet in the browser. The cooked post is not
  // changed, so emails, previews and no-JS readers still get the overview.
  // Only on real first posts of topics that expose project images (the
  // composer preview has no post model, so it's skipped).
  api.decorateCookedElement(
    (element, helper) => {
      if (element.querySelector(".npn-exhibition-mount")) {
        return;
      }
      const post = helper?.getModel?.();
      const images = post?.topic?.npn_project_images;
      if (
        !images?.originals?.length ||
        post?.post_number !== 1 ||
        !helper?.renderGlimmer
      ) {
        return;
      }

      const mount = document.createElement("div");
      mount.className = "npn-exhibition-mount";

      // Where the Project Overview grid sits (form posts), or at the top
      // (older posts read via the tag fallback). Its heading and grid are
      // hidden: the wall replaces them.
      const grid = element.querySelector(".npn-project-overview-grid");
      if (grid) {
        let heading = grid.previousElementSibling;
        while (heading && !/^H[1-6]$/.test(heading.tagName)) {
          heading = heading.previousElementSibling;
        }
        if (heading && /overview/i.test(heading.textContent)) {
          heading.classList.add("npn-replaced-by-exhibition");
          heading.before(mount);
        } else {
          grid.before(mount);
        }
        grid.classList.add("npn-replaced-by-exhibition");
      } else {
        element.prepend(mount);
      }

      helper.renderGlimmer(mount, NpnExhibitionWall, { images });
    },
    { id: "npn-exhibition-wall" }
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
