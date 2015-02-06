import AkismetQueue from 'discourse/plugins/discourse-akismet/admin/models/akismet-queue';

function genericError() {
  bootbox.alert(I18n.t('generic_error'));
}

export default Ember.ArrayController.extend({
  sortProperties: ["id"],
  sortAscending: true,
  enabled: false,
  performingAction: false,

  actions: {
    refresh() {
      var self = this;
      self.set('performingAction', true);
      AkismetQueue.findAll().then(function(result) {
        self.set('stats', result.stats);
        self.set('model', result.posts);
      }).catch(genericError).finally(function() {
        self.set('performingAction', false);
      });
    },

    confirmSpamPost(post){
      var self = this;
      self.set('performingAction', true);
      AkismetQueue.confirmSpam(post).then(function() {
        self.removeObject(post);
        self.incrementProperty('stats.confirmed_spam');
        self.decrementProperty('stats.needs_review');
      }).catch(genericError).finally(function() {
        self.set('performingAction', false);
      });
    },

    allowPost(post){
      var self = this;
      self.set('performingAction', true);
      AkismetQueue.allow(post).then(function() {
        self.incrementProperty('stats.confirmed_ham');
        self.decrementProperty('stats.needs_review');
        self.removeObject(post);
      }).catch(genericError).finally(function() {
        self.set('performingAction', false);
      });
    },

    deleteUser(post){
      var self = this;
      bootbox.confirm(I18n.t('akismet.delete_prompt', {username: post.get('username')}), function(result) {
        if (result === true) {
          self.set('performingAction', true);
          AkismetQueue.deleteUser(post).then(function() {
            self.removeObject(post);
            self.incrementProperty('stats.confirmed_spam');
            self.decrementProperty('stats.needs_review');
          }).catch(genericError).finally(function() {
            self.set('performingAction', false);
          });
        }
      });
    },
  }
});
