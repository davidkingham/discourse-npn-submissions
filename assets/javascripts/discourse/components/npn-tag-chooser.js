import { selectKitOptions } from "discourse/select-kit/components/select-kit";
import TagChooser from "discourse/select-kit/components/tag-chooser";
import NpnTagSelectedChoice from "./npn-tag-selected-choice";

// Thin TagChooser subclass used in unconstrained mode (when no descriptive
// tag group is configured). Core's `TagChooser` already wires
// `tag-chooser-row.gjs` for dropdown rows, which routes through
// `dDiscourseTag` and so already picks up Tag Icons. This subclass adds two
// things on top:
//   - `selectedChoiceComponent` — our tag-aware pill renderer so selected
//     chips also get the icon treatment.
//   - `useHeaderFilter: true` — switches the chooser to MiniTagChooser-style
//     "chips + filter live in the header" layout, so the selected chips are
//     visible whether the dropdown is open or closed (instead of the default
//     comma-separated plain-text summary shown in the closed header).
@selectKitOptions({
  selectedChoiceComponent: NpnTagSelectedChoice,
  useHeaderFilter: true,
})
export default class NpnTagChooser extends TagChooser {}
