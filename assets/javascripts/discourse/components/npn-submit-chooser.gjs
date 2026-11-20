import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

// `/submit` with no type: what would you like to do? The submission types are
// grouped by intent and each says in a line what it is for, so a member who
// doesn't know the forum's category names can still pick the right one.
const GROUPS = [
  {
    key: "share",
    types: [
      { type: "image", icon: "image" },
      { type: "weekly_challenge", icon: "calendar-week" },
      { type: "project", icon: "images" },
      { type: "new_member_image", icon: "seedling" },
    ],
  },
  { key: "hello", types: [{ type: "introduction", icon: "user-plus" }] },
  { key: "help", types: [{ type: "help", icon: "circle-question" }] },
];

export default class NpnSubmitChooser extends Component {
  // This week's challenge title, when WordPress sync has one.
  @tracked weeklyTitle = null;

  constructor() {
    super(...arguments);
    this.loadWeeklyChallenge();
  }

  // Decoration only: a failure leaves the card with its plain description.
  async loadWeeklyChallenge() {
    try {
      const result = await ajax("/npn-submissions/weekly-challenge");
      this.weeklyTitle = result.challenge?.title || null;
    } catch {
      this.weeklyTitle = null;
    }
  }

  get groups() {
    return GROUPS.map((group) => ({
      heading: i18n(`npn_submissions.chooser.groups.${group.key}`),
      cards: group.types.map(({ type, icon }) => ({
        icon,
        href: `/submit?type=${type}`,
        title: i18n(`npn_submissions.chooser.cards.${type}.title`),
        description: i18n(`npn_submissions.chooser.cards.${type}.description`),
        note:
          type === "weekly_challenge" && this.weeklyTitle
            ? i18n("npn_submissions.chooser.this_week", {
                title: this.weeklyTitle,
              })
            : null,
      })),
    }));
  }

  <template>
    <div class="npn-chooser">
      <h2 class="npn-chooser__heading">
        {{i18n "npn_submissions.chooser.heading"}}
      </h2>
      {{#each this.groups as |group|}}
        <section class="npn-chooser__group">
          <h3 class="npn-chooser__group-heading">{{group.heading}}</h3>
          <ul class="npn-chooser__cards">
            {{#each group.cards as |card|}}
              <li>
                <a class="npn-chooser__card" href={{card.href}}>
                  <span class="npn-chooser__icon">{{dIcon card.icon}}</span>
                  <span class="npn-chooser__text">
                    <span class="npn-chooser__title">{{card.title}}</span>
                    <span class="npn-chooser__description">
                      {{card.description}}
                    </span>
                    {{#if card.note}}
                      <span class="npn-chooser__note">{{card.note}}</span>
                    {{/if}}
                  </span>
                </a>
              </li>
            {{/each}}
          </ul>
        </section>
      {{/each}}
    </div>
  </template>
}
