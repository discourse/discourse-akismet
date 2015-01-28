export default Discourse.Route.extend({
  model: function() {
    return Discourse.ModQueue.findAll();
  },

  renderTemplate: function() {
    this.render("mod_queue_admin");
  }
});
