// import { lockdown } from '@endo/init/pre-remoting.js';
import '@endo/init/pre-remoting.js';
import { lockdown } from '@endo/lockdown';

// Needed for `zx`.
const options = {
  overrideTaming: 'severe',
  stackFiltering: 'verbose',
  errorTaming: 'unsafe',
};
lockdown(options);
