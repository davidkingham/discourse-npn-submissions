export default {
  resource: "admin.adminPlugins",
  path: "/plugins",

  map() {
    this.route("npn-submissions", function () {
      this.route("drafts");
      this.route("failed");
    });
  },
};
