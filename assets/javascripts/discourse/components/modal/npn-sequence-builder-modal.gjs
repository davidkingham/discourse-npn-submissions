import DModal from "discourse/ui-kit/d-modal";
import { i18n } from "discourse-i18n";
import NpnSequenceBuilder from "../npn-sequence-builder";

function insertAndClose(onInsert, closeModal) {
  return (markup) => {
    onInsert?.(markup);
    closeModal();
  };
}

// The Suggest-a-Sequence builder in a modal, for the plain reply composer.
// @model: { images, initial, onInsert(markup) }
const NpnSequenceBuilderModal = <template>
  <DModal
    @title={{i18n "npn_submissions.sequence.builder_title"}}
    @closeModal={{@closeModal}}
    class="npn-sequence-builder-modal"
  >
    <:body>
      <NpnSequenceBuilder
        @images={{@model.images}}
        @initial={{@model.initial}}
        @onInsert={{insertAndClose @model.onInsert @closeModal}}
        @onCancel={{@closeModal}}
      />
    </:body>
  </DModal>
</template>;

export default NpnSequenceBuilderModal;
