export default Ember.ArrayController.extend({
  sortProperties: ["id"],
  sortAscending: true,

  actions: {
    confirmSpamPost: function(cur_model){
      cur_model.confirmSpam().then(function(result){
        bootbox.alert(result.msg);
        this.removeObject(cur_model);
      }.bind(this));
    },

    allowPost: function(cur_model){
      cur_model.allow().then(function(result){
        bootbox.alert(result.msg);
        this.removeObject(cur_model);
      }.bind(this));
    },

    deleteUser: function(cur_model){
      var that = this;
      var msg = "Are you sure you want to delete " + cur_model.get("username") + "?  This will remove all of their posts and topics and block their email and ip address.";
      bootbox.confirm(msg, function(result) {
        if (result === true) {
          cur_model.deleteUser().then(function(result){
            bootbox.alert(result.msg);
            that.removeObject(cur_model);
          }.bind(this));
        }
      });
    },
  }
});
