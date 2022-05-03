import { E } from '@endo/eventual-send';

const deployContract = async (homePromise, { bundleSource, pathResolve }) => {
    console.log('awaiting home promise...');
    const home = await homePromise;
    const curState = await E(home.attMaker).getAccountState();
    console.log(curState);
    const BLD = { brand: curState.bonded.brand, unit: 1000000n };
    console.log(BLD);
    const mk = (kit, num) => harden({ brand: kit.brand, value: kit.unit * num });
    const amt = mk(BLD, 2n);
    console.log(amt);
    const runStake = await E(home.agoricNames).lookup('instance', 'runStake');
    const runStakeAPI = await E(home.zoe).getPublicFacet(runStake);
    const runStakeTerms = await E(home.zoe).getTerms(runStake);
    const attTerms = runStakeTerms.issuers.Attestation;
    console.log(attTerms);
    const attPmnt = await E(home.attMaker).makeAttestation(amt);
    const attAmount = await E(attIssuer).getAmountOf(attPmnt);
    console.log(attAmount);

    // const proposal = { give: { Attestation: attAmt }, want: { Debt: {brand:RUN.brand, value: 500000n } }};
    // E(home.zoe).offer(E(runStakeAPI).makeLoanInvitation(), proposal, { Attestation: attPmt })

};
  
export default deployContract;
