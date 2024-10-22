// @ts-check
import { getDenoms } from '../../utils.js';
import { AG0_MODE, COMMANDS } from '../../constants.js';

export async function homeRoute(req, res) {
  const denoms = await getDenoms();
  let denomHtml = '';
  denoms.forEach(denom => {
    denomHtml += `<label><input type="checkbox" name="denoms" value=${denom}> ${denom} </label>`;
  });
  const denomsDropDownHtml = `<div class="dropdown"> <div class="dropdown-content"> ${denomHtml}</div> </div>`;

  const clientText = !AG0_MODE
    ? `<input type="radio" id="client" name="command" value=${COMMANDS['SEND_AND_PROVISION_IST']} onclick="toggleRadio(event)">
  <label for="client">send IST and provision </label>
  <select name="clientType">
  <option value="SMART_WALLET">smart wallet</option>
  <option value="REMOTE_WALLET">ag-solo</option>
  </select>`
    : '';
  res.send(
    `<html><head><title>Faucet</title>
      <script>
      function toggleRadio(event) {
              var field = document.getElementById('denoms');
  
              if (event.target.value === "${COMMANDS['CUSTOM_DENOMS_LIST']}") {        
                field.style.display = 'block';
              } else if (field.style.display === 'block') {  
                 field.style.display = 'none';
              }
        }
      </script>
      
      <style>
        
        .dropdown {
        overflow: scroll;
        height: 120px;
        width: fit-content;
        }
  
        .dropdown-content {
          display: block;
          background-color: #f9f9f9;
          min-width: 160px;
          box-shadow: 0px 8px 16px 0px rgba(0,0,0,0.2);
        }
  
        .dropdown-content label {
          display: block;
          margin-top: 10px;
        }
        
        .denomsClass {
          display: none;
        }
  </style>
      </head><body><h1>welcome to the faucet</h1>
  <form action="/go" method="post">
  <label for="address">Address:</label> <input id="address" name="address" type="text" /><br>
  Request: <input type="radio" id="delegate" name="command" value=${COMMANDS['SEND_BLD/IBC']} checked="checked" onclick="toggleRadio(event)">
  <label for="delegate">send BLD/IBC toy tokens</label>
  ${clientText}
  
  <input type="radio" id=${COMMANDS['CUSTOM_DENOMS_LIST']} name="command" value=${COMMANDS['CUSTOM_DENOMS_LIST']} onclick="toggleRadio(event)"}>
  <label for=${COMMANDS['CUSTOM_DENOMS_LIST']}> Select Custom Denoms </label>
  
  <br>
  
  
  <br>
  <div id='denoms' class="denomsClass"> 
  Denoms: ${denomsDropDownHtml} <br> <br>
  </div>
  <input type="submit" />
  </form>
  <br>
  
  <br>
  <form action="/go" method="post">
  <input type="hidden" name="command" value=${COMMANDS['FUND_PROV_POOL']} /><input type="submit" value="fund provision pool" />
  </form>
  </body></html>
  `,
  );
}
