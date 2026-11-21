import { module, test } from "qunit";
import { chooseImageForm } from "discourse/plugins/discourse-npn-submissions/discourse/lib/npn-form-choice";

module("Unit | NPN Submissions | form choice", function () {
  test("the site default applies when nothing else is said", function (assert) {
    assert.strictEqual(
      chooseImageForm({ enabled: true, defaultNew: true }),
      "new"
    );
    assert.strictEqual(
      chooseImageForm({ enabled: true, defaultNew: false }),
      "classic"
    );
  });

  test("a member's last choice beats the default", function (assert) {
    assert.strictEqual(
      chooseImageForm({
        enabled: true,
        defaultNew: true,
        remembered: "classic",
      }),
      "classic"
    );
    assert.strictEqual(
      chooseImageForm({ enabled: true, defaultNew: false, remembered: "new" }),
      "new"
    );
    assert.strictEqual(
      chooseImageForm({ enabled: true, defaultNew: true, remembered: "junk" }),
      "new"
    );
  });

  test("the address beats both", function (assert) {
    assert.strictEqual(
      chooseImageForm({
        enabled: true,
        defaultNew: true,
        remembered: "new",
        param: "classic",
      }),
      "classic"
    );
    assert.strictEqual(
      chooseImageForm({
        enabled: true,
        defaultNew: false,
        remembered: "classic",
        param: "new",
      }),
      "new"
    );
  });

  test("switched off means classic, whatever is asked", function (assert) {
    assert.strictEqual(
      chooseImageForm({
        enabled: false,
        defaultNew: true,
        remembered: "new",
        param: "new",
      }),
      "classic"
    );
  });
});
