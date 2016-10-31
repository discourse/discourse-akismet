import { ajax } from 'discourse/lib/ajax';

export default {
  confirmSpam(post) {
    return ajax("/admin/plugins/akismet/confirm_spam", {
      type: "POST",
      data: {
        post_id: post.get("id")
      }
    });
  },

  allow(post) {
    return ajax("/admin/plugins/akismet/allow", {
      type: "POST",
      data: {
        post_id: post.get("id")
      }
    });
  },

  dismiss(post) {
    return ajax("/admin/plugins/akismet/dismiss", {
      type: "POST",
      data: {
        post_id: post.get("id")
      }
    });
  },

  deleteUser(post) {
    return ajax("/admin/plugins/akismet/delete_user", {
      type: "DELETE",
      data: {
        user_id: post.get("user_id"),
        post_id: post.get("id")
      }
    });
  },

  findAll() {
    return ajax("/admin/plugins/akismet/index.json").then(result => {
      result.posts = result.posts.map(p => Discourse.Post.create(p));
      return result;
    });
  }
};
