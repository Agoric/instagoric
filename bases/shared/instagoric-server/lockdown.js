import '@endo/init/pre-remoting.js';
import { lockdown } from '@endo/lockdown/pre.js';

const options = {
  overrideTaming: 'severe',
  stackFiltering: 'verbose',
  errorTaming: 'unsafe',
};
lockdown(options);
