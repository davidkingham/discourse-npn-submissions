import DModal from "discourse/ui-kit/d-modal";
import NpnHangSuggester from "../npn-hang-suggester";

function insertAndClose(onInsert, closeModal) {
  return (markup, label) => {
    onInsert?.(markup, label);
    closeModal();
  };
}

// "Suggest a hang" (or sequence / selection) in a modal, for the plain reply
// composer. @model: { images, initial, title, onInsert(markup, label) }
const NpnHangSuggesterModal = <template>
  <DModal
    @title={{@model.title}}
    @closeModal={{@closeModal}}
    class="npn-hang-suggester-modal"
  >
    <:body>
      <NpnHangSuggester
        @images={{@model.images}}
        @initial={{@model.initial}}
        @onInsert={{insertAndClose @model.onInsert @closeModal}}
        @onCancel={{@closeModal}}
      />
    </:body>
  </DModal>
</template>;

export default NpnHangSuggesterModal;
