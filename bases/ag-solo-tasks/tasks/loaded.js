import { E } from "@endo/eventual-send";

const deployContract = async (homePromise, { bundleSource, pathResolve }) => {
  console.log("awaiting home promise...");
  const home = await homePromise;
  if (home.LOADING !== undefined) {
    console.log("still loading");
    throw "still loading";
  }

  const issuerEntries = await E(home.wallet).getIssuers();
  const issuers = Object.fromEntries(issuerEntries);

  if (!("BLD" in issuers && "IST" in issuers)) {
    throw "still loading";
  }
  console.log("loaded");
};

export default deployContract;
