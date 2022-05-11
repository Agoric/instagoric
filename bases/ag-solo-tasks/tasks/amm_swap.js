import { E } from '@endo/eventual-send';

const deployContract = async (homePromise, { bundleSource, pathResolve }) => {
    console.log('awaiting home promise...');
    const home = await homePromise;
    const ammAPI = E(home.zoe).getPublicFacet(
        E(home.agoricNames).lookup('instance', 'amm'),
      );

    const issuerEntries = await E(home.wallet).getIssuers();
    const issuers = Object.fromEntries(issuerEntries);
    const brands = {
        BLD: await E(issuers.BLD).getBrand(),
        RUN: await E(issuers.RUN).getBrand(),
    };

    try {
        const bldPool = await E(ammAPI).addPool(issuers.BLD, 'BLDPool');
    } catch {}

    console.log("swap");
    const amt6 = (b, n) => ({ brand: b, value: n * 10n ** 6n });

    let removeLiquidity=false;
    // addLiquidityInvitation
    const purseEntries = await E(E(home.wallet).getAdminFacet()).getPurses();
    const [bldPurse] = purseEntries
        .filter(([label, _p]) => label.match(/Agoric staking token/i))
        .map(([_l, purse]) => purse);
    const [runPurse] = purseEntries
        .filter(([label, _p]) => label.match(/Agoric RUN currency/i))
        .map(([_l, purse]) => purse);
    var liquidity = null;
    var liquidityPayout = null;
    try {
        console.log("add liquidity")
        const addLiqInvitation = await E(ammAPI).makeAddLiquidityInvitation();
        const bldLiquidityIssuer = await E(ammAPI).getLiquidityIssuer(brands.BLD);
        const bldLiquidityBrand = await E(bldLiquidityIssuer).getBrand();

        const bldAmount = BigInt(Math.floor(Math.random() * 500)+1000);
        const runAmount = BigInt(Math.floor(Math.random() * 500)+1000);

        const proposalLiq = harden({
            want: { Liquidity: amt6(bldLiquidityBrand, 0n) },
            give: { Secondary: amt6(brands.BLD, bldAmount), Central: amt6(brands.RUN, runAmount) },
        });
        const pmtRun = await E(runPurse).withdraw(proposalLiq.give.Central);
        const pmtBld = await E(bldPurse).withdraw(proposalLiq.give.Secondary);

        const liqudityOfferSeat = await E(home.zoe).offer(addLiqInvitation, proposalLiq, 
            { Secondary: pmtBld, Central: pmtRun});
        const liquidityResult = await E(liqudityOfferSeat).getOfferResult();
        console.log(liquidityResult);
        liquidityPayout = await E(liqudityOfferSeat).getPayout('Liquidity');
        liquidity = await E(bldLiquidityIssuer).getAmountOf(liquidityPayout);
        console.log(liquidity);
        removeLiquidity = true;
        } catch {}
    console.log("swap bld for run");

    const toSwap = await E(ammAPI).makeSwapInvitation();
    const proposal = harden({
      want: { Out: amt6(brands.RUN, 0n) },
      give: { In: amt6(brands.BLD, 2n) },
    });
    const pmt = await E(bldPurse).withdraw(proposal.give.In);
    const seat = E(home.zoe).offer(toSwap, proposal, { In: pmt });
    const result = await E(seat).getOfferResult();
    console.log({ result });
    const got = await E(seat).getPayout('Out');
    const gotAmt = await E(issuers.RUN).getAmountOf(got);
    console.log({ gotAmt });

    console.log("swap run for bld");

    const toSwap2 = await E(ammAPI).makeSwapInvitation();
    const proposal2 = harden({
      want: { Out: amt6(brands.BLD, 0n) },
      give: { In: amt6(brands.RUN, 2n) },
    });
    const pmt2 = await E(runPurse).withdraw(proposal2.give.In);
    const seat2 = E(home.zoe).offer(toSwap2, proposal2, { In: pmt2 });
    const result2 = await E(seat2).getOfferResult();
    console.log({ result2 });
    const got2 = await E(seat2).getPayout('Out');
    const gotAmt2 = await E(issuers.BLD).getAmountOf(got2);
    console.log({ gotAmt2 });

    try {
      await E(bldPurse).deposit(got2);
    } catch {}
    
    if (removeLiquidity) {
        console.log("remove liquidity");
        const returnLiqInvitation = await E(ammAPI).makeRemoveLiquidityInvitation();
        const proposalRemoveLiq = harden({
            give: { Liquidity: liquidity },
            want: { Central: amt6(brands.RUN, 0n), Secondary: amt6(brands.BLD, 0n)},
        });
        console.log(proposalRemoveLiq);
        const liqudityRemoveOfferSeat = await E(home.zoe).offer(returnLiqInvitation, proposalRemoveLiq, 
            { Liquidity: liquidityPayout });
        const liquidityRemoveResult = await E(liqudityRemoveOfferSeat).getOfferResult();
        console.log(liquidityRemoveResult);
        const liquidityRemovePayoutCentral = await E(liqudityRemoveOfferSeat).getPayout('Central');
        const liquidityRemovePayoutSecondary = await E(liqudityRemoveOfferSeat).getPayout('Secondary');
        const liquidityCentral = await E(issuers.RUN).getAmountOf(liquidityRemovePayoutCentral);
        const liquiditySecondary = await E(issuers.BLD).getAmountOf(liquidityRemovePayoutSecondary);
        console.log(liquidityCentral, liquiditySecondary);
        await E(bldPurse).deposit(liquidityRemovePayoutSecondary);
        await E(runPurse).deposit(liquidityRemovePayoutCentral);
    }
    

    // withdraw liquidity
};
  
export default deployContract;
