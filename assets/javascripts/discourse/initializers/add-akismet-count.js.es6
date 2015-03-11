import { addFlagProperty } from 'discourse/controllers/header';

export default {
  name: 'add-akismet-count',

  initialize() {
    addFlagProperty('currentUser.akismet_review_count');
  }
};
