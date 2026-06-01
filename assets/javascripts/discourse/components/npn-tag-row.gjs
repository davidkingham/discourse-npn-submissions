import { classNames } from "@ember-decorators/component";
import SelectKitRowComponent from "discourse/select-kit/components/select-kit/select-kit-row";
import dDiscourseTag from "discourse/ui-kit/helpers/d-discourse-tag";

// Dropdown-row renderer for our tag MultiSelect (used when a descriptive tag
// group is configured). Mirrors core's `tag-chooser-row.gjs` — the only
// reason this exists is that plain `MultiSelect` renders generic rows via
// `<span class="name">{{rowName}}</span>`, which bypasses
// `dDiscourseTag` / `renderTag` and therefore never picks up the Tag Icons
// theme component's icon-injection. By routing through `dDiscourseTag` we
// flow through the `_renderer` that `api.replaceTagRenderer` overrides, so
// the theme component transparently does its thing.
//
// `TagChooser` (used when no descriptive tag group is set) already uses
// `tag-chooser-row.gjs` and so already gets icons; that path doesn't need
// this row component.
@classNames("npn-tag-row")
export default class NpnTagRow extends SelectKitRowComponent {
  <template>{{dDiscourseTag this.rowName noHref=true}}</template>
}
