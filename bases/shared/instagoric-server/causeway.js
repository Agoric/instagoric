// @ts-check

import { publicapp } from './app.js';
import driver from './neo4j.js';

publicapp.get('/causeway/interactions', async (request, response) => {
  if (!driver) response.send('No driver instance found for neo4j').status(500);
  else {
    const session = driver.session();

    try {
      const searchParams = request.query;
      const blockHeight = /** @type {string} */ (searchParams.blockHeight);
      const currentPage = Number(searchParams.currentPage) || 0;
      const endTime = /** @type {string} */ (searchParams.endTime);
      const limit = Number(searchParams.limit) || 20;
      const runId = /** @type {string} */ (searchParams.runId);
      const startTime = /** @type {string} */ (searchParams.startTime);

      const startTimestamp = parseFloat(startTime) || 0;
      const endTimestamp = parseFloat(endTime) || Math.floor(Date.now() / 1000);

      /**
       * @param {string} sourceNodeName
       * @param {string} targetNodeName
       */
      const createFilters = (sourceNodeName, targetNodeName) =>
        [
          blockHeight && `${sourceNodeName}.blockHeight = $blockHeight`,
          endTimestamp && `${sourceNodeName}.time <= $endTime`,
          runId && `${sourceNodeName}.runID = ${targetNodeName}.runID`,
          runId && `${sourceNodeName}.runID = $runId`,
          startTimestamp && `${sourceNodeName}.time >= $startTime`,
        ]
          .filter(Boolean)
          .join(' AND ');

      const query = `
          CALL {
            MATCH
              (message:Message)-[:CALL]->(target:Vat),
              (source:Vat)-[:SYSCALL]->(syscall:Syscall)
            WHERE
              message.result = syscall.result AND ${createFilters('message', 'syscall')}
            RETURN
              message.argSize     AS argSize,
              message.blockHeight AS blockHeight,
              message.crankNum    AS crankNum,
              message.elapsed     AS elapsed,
              message.method      AS method,
              message.result      AS promiseId,
              message.runID       AS runId,
              message.target      AS targetId,
              message.time        AS time,
              'message'           AS type,
              source.vatID        AS sourceVat,
              target.vatID        AS targetVat

            UNION ALL

            MATCH
              (notify:Notify)-[:CALL]->(target:Vat),
              (source:Vat)-[:RESOLVE]->(resolve:Resolve)
            WHERE
              notify.kpid = resolve.result AND ${createFilters('notify', 'resolve')}
            RETURN
              0                   AS argSize,
              notify.blockHeight  AS blockHeight,
              0                   AS crankNum,
              notify.elapsed      AS elapsed,
              notify.method       AS method,
              0                   AS promiseId,
              notify.runID        AS runId,
              notify.kpid         AS targetId,
              notify.time         AS time,
              'notify'            AS type,
              source.vatID        AS sourceVat,
              target.vatID        AS targetVat
          }
          RETURN *
          ORDER BY time
          OFFSET ${currentPage * limit}
          LIMIT ${limit};
        `;

      const result = await session.run(query, {
        blockHeight: Number(blockHeight),
        endTime: endTimestamp,
        runId,
        startTime: startTimestamp,
      });

      const interactions = result.records.map(record => ({
        argSize: record.get('argSize'),
        blockHeight: record.get('blockHeight'),
        crankNum: record.get('crankNum'),
        elapsed: record.get('elapsed'),
        method: record.get('method'),
        promiseId: record.get('promiseId'),
        runId: record.get('runId'),
        sourceVat: record.get('sourceVat'),
        targetId: record.get('targetId'),
        targetVat: record.get('targetVat'),
        time: record.get('time'),
        type: record.get('type'),
      }));

      response.send(interactions).status(200);
    } catch (error) {
      console.error('Error fetching interactions:', error);
      response.send('Failed to fetch interactions').status(500);
    } finally {
      await session.close();
    }
  }
});

publicapp.get('/causeway/interactions/count', async (request, response) => {
  if (!driver) response.send('No driver instance found for neo4j').status(500);
  else {
    const session = driver.session();

    try {
      const searchParams = request.query;
      const blockHeight = /** @type {string} */ (searchParams.blockHeight);
      const endTime = /** @type {string} */ (searchParams.endTime);
      const runId = /** @type {string} */ (searchParams.runId);
      const startTime = /** @type {string} */ (searchParams.startTime);

      const startTimestamp = parseFloat(startTime) || 0;
      const endTimestamp = parseFloat(endTime) || Math.floor(Date.now() / 1000);

      /**
       * @param {string} sourceNodeName
       * @param {string} targetNodeName
       */
      const createFilters = (sourceNodeName, targetNodeName) =>
        [
          blockHeight && `${sourceNodeName}.blockHeight = $blockHeight`,
          endTimestamp && `${sourceNodeName}.time <= $endTime`,
          runId && `${sourceNodeName}.runID = ${targetNodeName}.runID`,
          runId && `${sourceNodeName}.runID = $runId`,
          startTimestamp && `${sourceNodeName}.time >= $startTime`,
        ]
          .filter(Boolean)
          .join(' AND ');

      const countQuery = `
          CALL {
            MATCH
              (message:Message)-[:CALL]->(target:Vat),
              (source:Vat)-[:SYSCALL]->(syscall:Syscall)
            WHERE
              message.result = syscall.result AND ${createFilters('message', 'syscall')}
            RETURN count(*) AS messageCount
          }
          CALL {
            MATCH
              (notify:Notify)-[:CALL]->(target:Vat),
              (source:Vat)-[:RESOLVE]->(resolve:Resolve)
            WHERE
              notify.kpid = resolve.result AND ${createFilters('notify', 'resolve')}
            RETURN count(*) AS notifyCount
          }
          RETURN messageCount + notifyCount AS count;
        `;

      const countResult =
        /** @type {import('neo4j-driver').QueryResult<{count: number}>} */ (
          await session.run(countQuery, {
            blockHeight: Number(blockHeight),
            endTime: endTimestamp,
            runId,
            startTime: startTimestamp,
          })
        );

      response
        .send({
          interactionsCount: countResult.records.reduce(
            (total, record) => total + record.get('count'),
            0,
          ),
        })
        .status(200);
    } catch (error) {
      console.error('Error fetching interactions:', error);
      response.send('Failed to fetch interactions').status(500);
    } finally {
      await session.close();
    }
  }
});

publicapp.get('/causeway/vats', async (request, response) => {
  if (!driver) response.send('No driver instance found for neo4j').status(500);
  else {
    const session = driver.session();

    try {
      const searchParams = request.query;
      const blockHeight = /** @type {string} */ (searchParams.blockHeight);
      const endTime = /** @type {string} */ (searchParams.endTime);
      const runId = /** @type {string} */ (searchParams.runId);
      const startTime = /** @type {string} */ (searchParams.startTime);

      const endTimestamp = parseFloat(endTime) || Math.floor(Date.now() / 1000);
      const startTimestamp = parseFloat(startTime) || 0;

      const filters = [
        blockHeight && 'event.blockHeight = $blockHeight',
        endTimestamp && 'event.time <= $endTime',
        runId && 'event.runID = $runId',
        startTimestamp && 'event.time >= $startTime',
      ]
        .filter(Boolean)
        .join(' AND ');

      const result =
        /** @type {import('neo4j-driver').QueryResult<{ vatID: string; vatName: string }>} */ (
          await session.run(
            `
              MATCH (event)
              WHERE (event:Message OR event:Notify) AND ${filters}
              MATCH (event)-[:CALL]->(target:Vat)
              WITH collect(target) AS vatNodes
              UNWIND vatNodes AS v
              WITH DISTINCT v
              WHERE v IS NOT NULL
              RETURN
                v.vatID   AS vatID,
                v.name    AS vatName

            `,
            {
              blockHeight: Number(blockHeight),
              endTime: endTimestamp,
              runId,
              startTime: startTimestamp,
            },
          )
        );
      const vats = result.records.map(record => ({
        name: record.get('vatName'),
        vatID: record.get('vatID'),
      }));
      response.send(vats).status(200);
    } catch (error) {
      console.error('Error fetching vats:', error);
      response.send('Failed to fetch vats').status(500);
    } finally {
      await session.close();
    }
  }
});
