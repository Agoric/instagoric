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
      const runIds = /** @type {string} */ (searchParams.runIds || '')
        .split(',')
        .filter(Boolean);
      const startTime = /** @type {string} */ (searchParams.startTime);
      const vatIds = /** @type {string} */ (searchParams.vats || '')
        .split(',')
        .filter(Boolean);

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
          !!runIds.length &&
            `${sourceNodeName}.runID = ${targetNodeName}.runID`,
          !!runIds.length &&
            `${sourceNodeName}.runID IN ["${runIds.join('", "')}"]`,
          startTimestamp && `${sourceNodeName}.time >= $startTime`,
          !!vatIds.length && `source.vatID IN ["${vatIds.join('", "')}"]`,
          !!vatIds.length && `target.vatID IN ["${vatIds.join('", "')}"]`,
        ]
          .filter(Boolean)
          .join(' AND ');

      const query = `
          CALL() {
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
              message.methargs    AS methargs,
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
              0                   AS methargs,
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
        startTime: startTimestamp,
      });

      const interactions = result.records.map(record => ({
        argSize: record.get('argSize'),
        blockHeight: record.get('blockHeight'),
        crankNum: record.get('crankNum'),
        elapsed: record.get('elapsed'),
        methargs: record.get('methargs'),
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
      const runIds = /** @type {string} */ (searchParams.runIds || '')
        .split(',')
        .filter(Boolean);
      const startTime = /** @type {string} */ (searchParams.startTime);
      const vatIds = /** @type {string} */ (searchParams.vats || '')
        .split(',')
        .filter(Boolean);

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
          !!runIds.length &&
            `${sourceNodeName}.runID = ${targetNodeName}.runID`,
          !!runIds.length &&
            `${sourceNodeName}.runID IN ["${runIds.join('", "')}"]`,
          startTimestamp && `${sourceNodeName}.time >= $startTime`,
          !!vatIds.length && `source.vatID IN ["${vatIds.join('", "')}"]`,
          !!vatIds.length && `target.vatID IN ["${vatIds.join('", "')}"]`,
        ]
          .filter(Boolean)
          .join(' AND ');

      const countQuery = `
          CALL() {
            MATCH
              (message:Message)-[:CALL]->(target:Vat),
              (source:Vat)-[:SYSCALL]->(syscall:Syscall)
            WHERE
              message.result = syscall.result AND ${createFilters('message', 'syscall')}
            RETURN count(*) AS messageCount
          }
          CALL() {
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

publicapp.get('/causeway/run', async (request, response) => {
  if (!driver) response.send('No driver instance found for neo4j').status(500);
  else {
    const session = driver.session();

    try {
      const searchParams = request.query;

      const blockHeight = /** @type {string} */ (searchParams.blockHeight);
      const currentPage = Number(searchParams.currentPage) || 0;
      const endTime = /** @type {string} */ (searchParams.endTime);
      const id = /** @type {string} */ (searchParams.id);
      const limit = Number(searchParams.limit);
      const proposalId = /** @type {string} */ (searchParams.proposalId);
      const startTime = /** @type {string} */ (searchParams.startTime);

      const endTimestamp = parseFloat(endTime) || Math.floor(Date.now() / 1000);
      const startTimestamp = parseFloat(startTime) || 0;

      const filters = [
        blockHeight && 'run.blockHeight = $blockHeight',
        endTimestamp && 'run.time <= $endTime',
        id && 'run.id = $id',
        proposalId && 'run.proposalID = $proposalId',
        startTimestamp && 'run.time >= $startTime',
      ]
        .filter(Boolean)
        .join(' AND ');

      const result = /**
       * @type {import('neo4j-driver').QueryResult<{
       *  blockHeight: number;
       *  blockTime: number;
       *  computrons: number;
       *  id: string;
       *  number: string;
       *  proposalId: string;
       *  time: number
       *  triggerBundleHash: string;
       *  triggerMsgIdx: number;
       *  triggerSender: string;
       *  triggerSource: string;
       *  triggerTxHash: string;
       *  triggerType: string;
       * }>}
       */ (
        await session.run(
          `
            MATCH (run:Run)
            ${filters.length ? ` WHERE ${filters}` : ''}
            RETURN
              run.blockHeight           AS blockHeight,
              run.blockTime             AS blockTime,
              run.computrons            AS computrons,
              run.id                    AS id,
              run.number                AS number,
              run.proposalID            AS proposalId,
              run.time                  AS time,
              run.triggerBundleHash     AS triggerBundleHash,
              run.triggerMsgIdx         AS triggerMsgIdx,
              run.triggerSender         AS triggerSender,
              run.triggerSource         AS triggerSource,
              run.triggerTxHash         AS triggerTxHash,
              run.triggerType           AS triggerType
            OFFSET ${currentPage * (limit || 1)}
            ${limit ? ` LIMIT ${limit}` : ''};
          `,
          {
            blockHeight: Number(blockHeight),
            endTime: endTimestamp,
            id,
            proposalId,
            startTime: startTimestamp,
          },
        )
      );
      const runs = result.records.map(record => record.toObject());
      response.send(runs).status(200);
    } catch (error) {
      console.error('Error fetching runs:', error);
      response.send('Failed to fetch runs').status(500);
    } finally {
      await session.close();
    }
  }
});

publicapp.get('/causeway/run-ids', async (request, response) => {
  if (!driver) response.send('No driver instance found for neo4j').status(500);
  else {
    const session = driver.session();

    try {
      const searchParams = request.query;
      const blockHeight = /** @type {string} */ (searchParams.blockHeight);
      const endTime = /** @type {string} */ (searchParams.endTime);
      const startTime = /** @type {string} */ (searchParams.startTime);

      const endTimestamp = parseFloat(endTime) || Math.floor(Date.now() / 1000);
      const startTimestamp = parseFloat(startTime) || 0;

      const filters = [
        blockHeight && 'event.blockHeight = $blockHeight',
        endTimestamp && 'event.time <= $endTime',
        startTimestamp && 'event.time >= $startTime',
      ]
        .filter(Boolean)
        .join(' AND ');

      const result =
        /** @type {import('neo4j-driver').QueryResult<{ runID: string }>} */ (
          await session.run(
            `
              MATCH (event)
              WHERE (event:Message OR event:Notify) AND ${filters}
              MATCH (event)-[:CALL]->(:Vat)
              WITH collect(event) AS events
              UNWIND events AS event
              WITH DISTINCT event.runID AS runID
              WHERE runID IS NOT NULL
              RETURN runID

            `,
            {
              blockHeight: Number(blockHeight),
              endTime: endTimestamp,
              startTime: startTimestamp,
            },
          )
        );
      const uniqueRunIds = result.records.map(record => record.get('runID'));
      response.send(uniqueRunIds).status(200);
    } catch (error) {
      console.error('Error fetching vats:', error);
      response.send('Failed to fetch vats').status(500);
    } finally {
      await session.close();
    }
  }
});

publicapp.get(
  '/causeway/transaction/:transactionId/run-id',
  async (request, response) => {
    if (!driver)
      response.send('No driver instance found for neo4j').status(500);
    else {
      const session = driver.session();
      const transactionId = request.params.transactionId;

      try {
        const triggerSource = /** @type {string} */ (request.query.source);

        const filters = [
          triggerSource && 'run.triggerSource = $source',
          'run.triggerTxHash = $transactionId',
          'run.triggerType = "bridge"',
        ]
          .filter(Boolean)
          .join(' AND ');

        const result =
          /** @type {import('neo4j-driver').QueryResult<{ runID: string }>} */ (
            await session.run(
              `
              MATCH (run:Run)
              WHERE ${filters}
              RETURN DISTINCT run.id AS runID;
            `,
              {
                transactionId,
                source: triggerSource,
              },
            )
          );

        if (!result.records.length)
          response
            .send(`No run found for transaction "${transactionId}"`)
            .status(404);
        else
          response
            .send(result.records.map(record => record.get('runID')))
            .status(200);
      } catch (error) {
        console.error(
          `Error fetching run ID for transaction "${transactionId}": `,
          error,
        );
        response
          .send(`Failed to fetch run ID for transaction "${transactionId}"`)
          .status(500);
      } finally {
        await session.close();
      }
    }
  },
);

publicapp.get('/causeway/vats', async (request, response) => {
  if (!driver) response.send('No driver instance found for neo4j').status(500);
  else {
    const session = driver.session();

    try {
      const searchParams = request.query;
      const blockHeight = /** @type {string} */ (searchParams.blockHeight);
      const endTime = /** @type {string} */ (searchParams.endTime);
      const runIds = /** @type {string} */ (searchParams.runIds || '')
        .split(',')
        .filter(Boolean);
      const startTime = /** @type {string} */ (searchParams.startTime);
      const vatIds = /** @type {string} */ (searchParams.vats || '')
        .split(',')
        .filter(Boolean);

      const endTimestamp = parseFloat(endTime) || Math.floor(Date.now() / 1000);
      const startTimestamp = parseFloat(startTime) || 0;

      const filters = [
        blockHeight && 'event.blockHeight = $blockHeight',
        endTimestamp && 'event.time <= $endTime',
        !!runIds.length && `event.runID IN ["${runIds.join('", "')}"]`,
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
              WHERE v IS NOT NULL ${vatIds.length ? `AND v.vatID IN ["${vatIds.join('", "')}"]` : ''}
              RETURN
                v.vatID   AS vatID,
                v.name    AS vatName

            `,
            {
              blockHeight: Number(blockHeight),
              endTime: endTimestamp,
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
