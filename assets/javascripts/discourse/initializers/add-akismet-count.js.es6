import { withPluginApi } from 'discourse/lib/plugin-api';

export default {
  name: 'add-akismet-count',
  before: 'register-discourse-location',
  after: 'inject-objects',

  initialize(container) {
    const user = container.lookup('current-user:main');

    if (user && user.get('staff')) {

      let added = false;
      withPluginApi('0.4', api => {
        api.addFlagProperty('currentUser.akismet_review_count');
        added = true;

        api.decorateWidget('hamburger-menu:admin-links', dec => {
          return dec.attach('link', {
            route: 'adminPlugins.akismet',
            label: 'akismet.title',
            badgeCount: 'akismet_review_count',
            badgeClass: 'flagged-posts'
          });
        });

      });

      // if the api didn't activate, try the module way
      if (!added) {
        const headerMod = require('discourse/controllers/header');
        if (headerMod && headerMod.addFlagProperty) {
          headerMod.addFlagProperty('currentUser.akismet_review_count');
        }
      }

      const messageBus = container.lookup('message-bus:main');
      messageBus.subscribe("/akismet_counts", function(result) {
        if (result) {
          user.set('akismet_review_count', result.akismet_review_count || 0);
        }
      });
    }
  }
};
