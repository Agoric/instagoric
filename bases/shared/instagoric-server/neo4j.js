// @ts-check

import neo4j, { Driver } from 'neo4j-driver';

/** @type {Driver | undefined} */
let driverInstance = undefined;

const getDriver = () => {
  if (
    !driverInstance &&
    process.env.NEO4J_URI &&
    process.env.NEO4J_USER &&
    process.env.NEO4J_PASSWORD
  )
    driverInstance = neo4j.driver(
      process.env.NEO4J_URI,
      neo4j.auth.basic(process.env.NEO4J_USER, process.env.NEO4J_PASSWORD),
      {
        disableLosslessIntegers: true,
      },
    );
  return driverInstance;
};

const driver = getDriver();

export default driver;
