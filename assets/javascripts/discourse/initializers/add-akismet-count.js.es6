import { addFlagProperty } from 'discourse/controllers/header';

export default {
  name: 'add-akismet-count',

  initialize(container) {
    addFlagProperty('currentUser.akismet_review_count');

    const user = container.lookup('current-user:main');

    if (user && user.get('staff')) {
      const messageBus = container.lookup('message-bus:main');
      messageBus.subscribe("/akismet_counts", function(result) {
        if (result) {
          user.set('akismet_review_count', result.akismet_review_count || 0);
        }
      });
    }
  }
};
