import AkismetQueue from 'discourse/plugins/discourse-akismet/admin/models/akismet-queue';

export default Discourse.Route.extend({
  _enabled: false,

  model: function() {
    var self = this;
    return AkismetQueue.findAll().then(function(result) {
      self._enabled = result.enabled;
      return result.posts;
    });
  },

  setupController: function(controller, model) {
    controller.setProperties({ model: model, enabled: this._enabled });
  }
});
