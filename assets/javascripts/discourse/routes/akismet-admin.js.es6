import AkismetQueue from 'discourse/plugins/discourse-akismet/admin/models/akismet-queue';

export default Discourse.Route.extend({
  model: function() {
    return AkismetQueue.findAll();
  }
});
