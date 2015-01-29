import AkismetQueue from 'discourse/plugins/discourse-akismet/admin/models/akismet-queue';

function genericError() {
  bootbox.alert(I18n.t('generic_error'));
}

export default Ember.ArrayController.extend({
  sortProperties: ["id"],
  sortAscending: true,

  actions: {
    confirmSpamPost: function(post){
      var self = this;
      AkismetQueue.confirmSpam(post).then(function(result) {
        bootbox.alert(result.msg);
        self.removeObject(post);
      }).catch(genericError);
    },

    allowPost: function(post){
      var self = this;
      AkismetQueue.allow(post).then(function(result) {
        bootbox.alert(result.msg);
        self.removeObject(post);
      }).catch(genericError);
    },

    deleteUser: function(post){

      var self = this;
      bootbox.confirm(I18n.t('akismet.delete_prompt', {username: post.get('username')}), function(result) {
        if (result === true) {
          AkismetQueue.deleteUser(post).then(function(result){
            bootbox.alert(result.msg);
            self.removeObject(post);
          }).catch(genericError);
        }
      });
    },
  }
});
