import { apiInitializer } from "discourse/lib/api";
import { containsSequence } from "../lib/npn-sequence";

// Adds a "Suggest a sequence" button to the composer toolbar when replying on
// an image-method project topic. Selecting an inserted sequence image first
// (in the Markdown editor) and clicking the button reopens it for editing.
export default apiInitializer((api) => {
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
