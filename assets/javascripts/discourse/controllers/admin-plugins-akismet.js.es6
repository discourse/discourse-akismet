import AkismetQueue from "discourse/plugins/discourse-akismet/admin/models/akismet-queue";

function genericError() {
  bootbox.alert(I18n.t("generic_error"));
}

export default Ember.Controller.extend({
  sortedPosts: Ember.computed.sort("model", "postSorting"),
  postSorting: ["id:asc"],
  enabled: false,
  performingAction: false,

  actions: {
    refresh() {
      this.set("performingAction", true);
      AkismetQueue.findAll()
        .then(result => {
          this.set("stats", result.stats);
          this.set("model", result.posts);
        })
        .catch(genericError)
        .finally(() => {
          this.set("performingAction", false);
        });
    },

    confirmSpamPost(post) {
      this.set("performingAction", true);
      AkismetQueue.confirmSpam(post)
        .then(() => {
          this.get("model").removeObject(post);
          this.incrementProperty("stats.confirmed_spam");
          this.decrementProperty("stats.needs_review");
        })
        .catch(genericError)
        .finally(() => {
          this.set("performingAction", false);
        });
    },

    allowPost(post) {
      this.set("performingAction", true);
      AkismetQueue.allow(post)
        .then(() => {
          this.incrementProperty("stats.confirmed_ham");
          this.decrementProperty("stats.needs_review");
          this.get("model").removeObject(post);
        })
        .catch(genericError)
        .finally(() => {
          this.set("performingAction", false);
        });
    },

    deleteUser(post) {
      bootbox.confirm(
        I18n.t("akismet.delete_prompt", { username: post.get("username") }),
        result => {
          if (result === true) {
            this.set("performingAction", true);
            AkismetQueue.deleteUser(post)
              .then(() => {
                this.get("model").removeObject(post);
                this.incrementProperty("stats.confirmed_spam");
                this.decrementProperty("stats.needs_review");
              })
              .catch(genericError)
              .finally(() => {
                this.set("performingAction", false);
              });
          }
        }
      );
    },

    dismiss(post) {
      this.set("performingAction", true);
      AkismetQueue.dismiss(post)
        .then(() => {
          this.get("model").removeObject(post);
        })
        .catch(genericError)
        .finally(() => {
          this.set("performingAction", false);
        });
    }
  }
});
