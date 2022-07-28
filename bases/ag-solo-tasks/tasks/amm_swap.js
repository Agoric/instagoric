/* global process */
import { E } from "@endo/eventual-send";
import { AmountMath } from "@agoric/ertp";

const deployContract = async (homePromise, { bundleSource, pathResolve }) => {
  console.log("awaiting home promise...");
  const home = await homePromise;
  let wall = +new Date();
  const ammInstance = await E(home.agoricNames).lookup("instance", "amm");
  const ammAPI = E(home.zoe).getPublicFacet(ammInstance);

  const issuerEntries = await E(home.wallet).getIssuers();
  const issuers = Object.fromEntries(issuerEntries);
  const [bldBrand, istBrand] = await Promise.all([
    E(issuers.BLD).getBrand(),
    E(issuers.IST).getBrand(),
  ]);
  const brands = {
    BLD: bldBrand,
    IST: istBrand,
  };
  console.log(
    JSON.stringify({
      worker: process.env.PODNAME || "unknown",
      log_metric: "log_metric",
      action: "bootstrap",
      script: "amm_swap",
      dur: +new Date() - wall,
    })
  );
  const amt6 = (b, n) => ({ brand: b, value: n * 10n ** 6n });
  const purseEntries = await E(E(home.wallet).getAdminFacet()).getPurses();
  const [bldPurse] = purseEntries
    .filter(([label, _p]) => label.match(/Agoric staking token/i))
    .map(([_l, purse]) => purse);
  const [istPurse] = purseEntries
    .filter(([label, _p]) => label.match(/Agoric stable local currency/i))
    .map(([_l, purse]) => purse);

  try {
    const poolName = "BLDPool";
    var poolAlloc = undefined;
    try {
      poolAlloc = await E(ammAPI).getPoolAllocation(brands.BLD);
    } catch {}
    if (poolAlloc === undefined) {
      try {
        const liquidityIssuer = await E(ammAPI).addIssuer(
          issuers.BLD,
          poolName
        );
      } catch (err) {
        console.log(err);
      }
      const allIssuers = await E(home.zoe).getIssuers(ammInstance);
      const liquidityIssuer = allIssuers[`${poolName}Liquidity`];
      const [liquidityBrand, addPoolInvite] = await Promise.all([
        E(liquidityIssuer).getBrand(),
        E(ammAPI).addPoolInvitation(),
      ]);

      const fundPoolProposal = harden({
        give: {
          Secondary: amt6(brands.BLD, 300n),
          Central: amt6(brands.IST, 1500n),
        },
        want: { Liquidity: AmountMath.make(liquidityBrand, 1000n) },
      });
      const [sec, cen] = await Promise.all([
        E(bldPurse).withdraw(fundPoolProposal.give.Secondary),
        E(istPurse).withdraw(fundPoolProposal.give.Central),
      ]);
      const payments = {
        Secondary: sec,
        Central: cen,
      };

      const addPoolSeat = await E(home.zoe).offer(
        addPoolInvite,
        fundPoolProposal,
        payments
      );

      const offerResult = await E(addPoolSeat).getOfferResult();
      console.log(offerResult);
    } else {
      console.log("pool exists");
    }
  } catch (err) {
    console.log(err);
  }

  console.log("swap");

  let removeLiquidity = false;
  // addLiquidityInvitation
  var liquidity = null;
  var liquidityPayout = null;
  try {
    wall = +new Date();
    console.log("add liquidity");
    const addLiqInvitation = await E(ammAPI).makeAddLiquidityInvitation();
    const bldLiquidityIssuer = await E(ammAPI).getLiquidityIssuer(brands.BLD);
    const bldLiquidityBrand = await E(bldLiquidityIssuer).getBrand();

    const bldAmount = BigInt(Math.floor(Math.random() * 500) + 1000);
    const istAmount = BigInt(Math.floor(Math.random() * 500) + 1000);

    const proposalLiq = harden({
      want: { Liquidity: amt6(bldLiquidityBrand, 0n) },
      give: {
        Secondary: amt6(brands.BLD, bldAmount),
        Central: amt6(brands.IST, istAmount),
      },
    });
    const [pmtIst, pmtBld] = await Promise.all([
      E(istPurse).withdraw(proposalLiq.give.Central),
      E(bldPurse).withdraw(proposalLiq.give.Secondary),
    ]);

    const liqudityOfferSeat = await E(home.zoe).offer(
      addLiqInvitation,
      proposalLiq,
      { Secondary: pmtBld, Central: pmtIst }
    );
    const liquidityResult = await E(liqudityOfferSeat).getOfferResult();
    console.log(liquidityResult);
    liquidityPayout = await E(liqudityOfferSeat).getPayout("Liquidity");
    liquidity = await E(bldLiquidityIssuer).getAmountOf(liquidityPayout);
    console.log(liquidity);
    removeLiquidity = true;
    console.log(
      JSON.stringify({
        worker: process.env.PODNAME || "unknown",
        log_metric: "log_metric",
        action: "add_liquidity",
        script: "amm_swap",
        dur: +new Date() - wall,
      })
    );
  } catch (err) {
    console.log(err);
  }
  console.log("swap bld for ist");
  wall = +new Date();
  const proposal = harden({
    want: { Out: amt6(brands.IST, 0n) },
    give: { In: amt6(brands.BLD, 2n) },
  });
  const [toSwap, pmt] = await Promise.all([
    E(ammAPI).makeSwapInvitation(),
    E(bldPurse).withdraw(proposal.give.In),
  ]);
  const seat = E(home.zoe).offer(toSwap, proposal, { In: pmt });
  const result = await E(seat).getOfferResult();
  console.log({ result });
  const got = await E(seat).getPayout("Out");
  const gotAmt = await E(issuers.IST).getAmountOf(got);
  console.log({ gotAmt });
  console.log(
    JSON.stringify({
      worker: process.env.PODNAME || "unknown",
      log_metric: "log_metric",
      action: "swap_in",
      script: "amm_swap",
      dur: +new Date() - wall,
    })
  );

  console.log("swap ist for bld");
  wall = +new Date();
  const proposal2 = harden({
    want: { Out: amt6(brands.BLD, 0n) },
    give: { In: amt6(brands.IST, 2n) },
  });
  const [toSwap2, pmt2] = await Promise.all([
    E(ammAPI).makeSwapInvitation(),
    E(istPurse).withdraw(proposal2.give.In),
  ]);
  const seat2 = E(home.zoe).offer(toSwap2, proposal2, { In: pmt2 });
  const result2 = await E(seat2).getOfferResult();
  console.log({ result2 });
  const got2 = await E(seat2).getPayout("Out");
  const gotAmt2 = await E(issuers.BLD).getAmountOf(got2);
  console.log({ gotAmt2 });
  console.log(
    JSON.stringify({
      worker: process.env.PODNAME || "unknown",
      log_metric: "log_metric",
      action: "swap_out",
      script: "amm_swap",
      dur: +new Date() - wall,
    })
  );

  try {
    await E(bldPurse).deposit(got2);
  } catch {}

  if (removeLiquidity) {
    wall = +new Date();
    console.log("remove liquidity");
    const returnLiqInvitation = await E(ammAPI).makeRemoveLiquidityInvitation();
    const proposalRemoveLiq = harden({
      give: { Liquidity: liquidity },
      want: { Central: amt6(brands.IST, 0n), Secondary: amt6(brands.BLD, 0n) },
    });
    console.log(proposalRemoveLiq);
    const liqudityRemoveOfferSeat = await E(home.zoe).offer(
      returnLiqInvitation,
      proposalRemoveLiq,
      { Liquidity: liquidityPayout }
    );
    const liquidityRemoveResult = await E(
      liqudityRemoveOfferSeat
    ).getOfferResult();
    console.log(liquidityRemoveResult);
    const [liquidityRemovePayoutCentral, liquidityRemovePayoutSecondary] =
      await Promise.all([
        E(liqudityRemoveOfferSeat).getPayout("Central"),
        E(liqudityRemoveOfferSeat).getPayout("Secondary"),
      ]);

    const [liquidityCentral, liquiditySecondary] = await Promise.all([
      E(issuers.IST).getAmountOf(liquidityRemovePayoutCentral),
      E(issuers.BLD).getAmountOf(liquidityRemovePayoutSecondary),
    ]);
    console.log(liquidityCentral, liquiditySecondary);
    await Promise.all([
      E(bldPurse).deposit(liquidityRemovePayoutSecondary),
      E(istPurse).deposit(liquidityRemovePayoutCentral),
    ]);

    console.log(
      JSON.stringify({
        worker: process.env.PODNAME || "unknown",
        log_metric: "log_metric",
        action: "remove_liquidity",
        script: "amm_swap",
        dur: +new Date() - wall,
      })
    );
  }

  // withdraw liquidity
};

export default deployContract;
