import { click, fillIn, visit } from "@ember/test-helpers";
import { test } from "qunit";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";

// The profile Setup page (/setup) persists the geocoded location chosen via
// discourse-npn-locations' LocationSelector into the `geo_location` user custom
// field, as a JSON string, through core's PUT /u/:username. These tests assert
// that contract end to end (a prefilled value, and a fresh search → pick).

const USER_GEO_LOCATION = {
  lat: "51.5073219",
  lon: "-0.1276474",
  address: "London, Greater London, England, United Kingdom",
  countrycode: "gb",
  city: "London",
  state: "England",
  country: "United Kingdom",
  postalcode: "",
  type: "city",
};

const SEARCH_RESULT = {
  lat: 53.4058473,
  lon: -2.995843140624263,
  address:
    "Royal Liver Building, Water Street, Liverpool, L3 1EG, United Kingdom",
  countrycode: "gb",
  city: "Liverpool",
  state: "England",
  country: "United Kingdom",
  postalcode: "L3 1EG",
  type: "attraction",
};

const LOCATION_SEARCH_RESPONSE = {
  locations: [SEARCH_RESULT],
  provider: "nominatim",
};

// Minimal /u/:username.json body — findDetails only post-processes stats/groups/
// badges when present, so omitting them is fine. Don't include username_lower:
// it's a computed property on the User model and setProperties() can't assign it.
function userDetailsResponse(overrides = {}) {
  return {
    user: {
      id: 19,
      username: "eviltrout",
      name: "Robin Ward",
      can_edit: true,
      bio_raw: "Hello there",
      website: "https://eviltrout.com",
      avatar_template: "/letter_avatar/eviltrout/{size}/abc.png",
      user_option: {},
      custom_fields: {},
      ...overrides,
    },
  };
}

// user.save() PUTs form-encoded data, so a nested custom_fields object becomes
// `custom_fields[geo_location]=<json>` in the request body.
function geoLocationFromPut(requestBody) {
  return new URLSearchParams(requestBody).get("custom_fields[geo_location]");
}

acceptance(
  "NPN Submissions | Setup profile | saves a prefilled location",
  function (needs) {
    let putBody = null;

    needs.user({ username: "eviltrout", id: 19 });
    needs.settings({
      npn_submissions_enabled: true,
      location_enabled: true,
      location_geocoding_debounce: 0,
    });
    needs.pretender((server, helper) => {
      server.get("/u/eviltrout.json", () =>
        helper.response(
          userDetailsResponse({
            geo_location: USER_GEO_LOCATION,
            custom_fields: { geo_location: USER_GEO_LOCATION },
          })
        )
      );
      server.put("/u/eviltrout.json", (request) => {
        putBody = request.requestBody;
        return helper.response({ user: {} });
      });
    });

    test("sends geo_location as a JSON string on save", async function (assert) {
      await visit("/setup");
      assert
        .dom(".npn-setup-form__location-field")
        .exists("location field shows");

      await click(".npn-image-form__actions .btn-primary");

      const raw = geoLocationFromPut(putBody);
      assert.strictEqual(
        typeof raw,
        "string",
        "custom_fields[geo_location] is included in the PUT"
      );
      assert.deepEqual(
        JSON.parse(raw),
        USER_GEO_LOCATION,
        "the prefilled geo object is persisted as a JSON string"
      );
    });
  }
);

acceptance(
  "NPN Submissions | Setup profile | geocodes and saves a searched location",
  function (needs) {
    let putBody = null;

    needs.user({ username: "eviltrout", id: 19 });
    needs.settings({
      npn_submissions_enabled: true,
      location_enabled: true,
      location_geocoding_debounce: 0,
    });
    needs.pretender((server, helper) => {
      server.get("/u/eviltrout.json", () =>
        helper.response(userDetailsResponse())
      );
      server.get("/locations/search", () =>
        helper.response(LOCATION_SEARCH_RESPONSE)
      );
      server.put("/u/eviltrout.json", (request) => {
        putBody = request.requestBody;
        return helper.response({ user: {} });
      });
    });

    test("searching, picking a result, and saving stores it as geo_location", async function (assert) {
      await visit("/setup");

      // Open the LocationSelector dropdown, search, and pick the first result.
      await click(
        ".npn-setup-form__location-field .geo-d-multi-select-trigger"
      );
      await fillIn(".d-multi-select__search-input", "liver building");
      await click(".d-multi-select__result:nth-child(1)");

      await click(".npn-image-form__actions .btn-primary");

      const raw = geoLocationFromPut(putBody);
      assert.strictEqual(
        typeof raw,
        "string",
        "custom_fields[geo_location] is included in the PUT"
      );
      const geo = JSON.parse(raw);
      assert.strictEqual(
        geo.address,
        SEARCH_RESULT.address,
        "the picked address is persisted"
      );
      assert.strictEqual(
        geo.lat,
        SEARCH_RESULT.lat,
        "the picked latitude is persisted"
      );
      assert.strictEqual(
        geo.lon,
        SEARCH_RESULT.lon,
        "the picked longitude is persisted"
      );
    });
  }
);
