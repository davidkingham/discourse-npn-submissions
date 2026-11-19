import { apiInitializer } from "discourse/lib/api";
import NpnExhibitionWall from "../components/npn-exhibition-wall";
import { containsSuggestion } from "../lib/npn-hang-suggestion";

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

      // Replace, in order of preference: the drawn hang image (posts made
      // with "Hang your show"), the Project Overview grid (earlier form
      // posts), or nothing (older posts read via the tag fallback: the wall
      // goes at the top). The replaced heading and block are hidden.
      const target =
        element.querySelector(".npn-project-hang") ||
        element.querySelector(".npn-project-overview-grid");
      if (target) {
        let heading = target.previousElementSibling;
        while (heading && !/^H[1-6]$/.test(heading.tagName)) {
          heading = heading.previousElementSibling;
        }
        if (
          heading &&
          /overview|exhibition|gallery|sequence|selection/i.test(
            heading.textContent
          )
        ) {
          heading.classList.add("npn-replaced-by-exhibition");
          heading.before(mount);
        } else {
          target.before(mount);
        }
        target.classList.add("npn-replaced-by-exhibition");
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
      title: "npn_submissions.suggest.toolbar_title",
      preventFocus: true,
      condition: () => !!projectImages(),
      action: (toolbarEvent) => {
        const images = projectImages();
        if (!images) {
          return;
        }
        const selectedText = toolbarEvent.selected?.value;
        const editing = containsSuggestion(selectedText);
        builder.open({
          images,
          selectedText: editing ? selectedText : null,
          // Replace a selected suggestion in place; otherwise replace one
          // with the same label, or insert it as its own block.
          onInsert: (markup, label) =>
            editing
              ? toolbarEvent.addText(markup)
              : builder.insertIntoComposer(markup, label),
        });
      },
    });
  });
});
