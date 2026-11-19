import NpnProjectStrip from "../../components/npn-project-strip";

// Reply composer on an image-method project topic → numbered project strip +
// Suggest-a-Sequence button. Renders nothing anywhere else.
const NpnProjectStripConnector = <template>
  <NpnProjectStrip @model={{@outletArgs.model}} />
</template>;

export default NpnProjectStripConnector;
