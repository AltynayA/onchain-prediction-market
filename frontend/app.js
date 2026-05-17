// contract addresses on Base Sepolia (chain 84532)
const ADDRESSES = {
  market:       "0x0cEC8fd1fD75bFe985807BeEEC1ACdaBE1784bB7",
  cpmm:         "0x903FB4d0A0c7FA3a076D900039737B0b059A1d79",
  collateral:   "0x8fAC0f9B73DaC33f6d981A58a2De2C9a61A5d50C",
  outcomeToken: "0x8A6A50Db75992c17e9adFde99818921757521B3e",
  feeVault:     "0x89a375715161F7221a890eB7dE11086d9Aa0DE84",
  govToken:     "0xA7086085727494305CD37E13adF446c096B24e70",
  governor:     "0xBdF66e0A87a5759444ec0b585BDf581Ce3Ef309E",
  timelock:     "0xE699943a7d8b351E8c30064dB3511278D5f58042",
};

const BASE_SEPOLIA_CHAIN_ID = "0x14a34"; // 84532 in hex

// minimal ABIs
const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function decimals() view returns (uint8)",
];

const GOV_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function getVotes(address) view returns (uint256)",
  "function delegates(address) view returns (address)",
  "function delegate(address delegatee)",
];

const MARKET_ABI = [
  "function getMarket(uint256) view returns (tuple(string question, uint256 resolutionTime, uint256 disputeDeadline, uint256 totalCollateral, uint256 yesShares, uint256 noShares, uint8 state, bool outcome, address oracleAdapter))",
  "function buyShares(uint256 marketId, bool isYes, uint256 amountIn, uint256 minShares)",
];

const CPMM_ABI = [
  "function reserveYes() view returns (uint256)",
  "function reserveNo() view returns (uint256)",
  "function impliedProbabilityYes() view returns (uint256)",
];

const VAULT_ABI = [
  "function totalAssets() view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function deposit(uint256 assets, address receiver) returns (uint256)",
];

const GOVERNOR_ABI = [
  "function castVote(uint256 proposalId, uint8 support) returns (uint256)",
];

// subgraph endpoint (The Graph — Base Sepolia)
const SUBGRAPH_URL = "https://api.goldsky.com/api/public/project_cmp9m4o9exste01uedkt57uez/subgraphs/prediction-market/1.0.0/gn";

const MARKET_STATES = ["Active", "Pending", "Disputed", "Final"];

// global state
let provider = null;
let signer = null;
let userAddress = null;
let buyYes = true;

// wallet connection 

async function connectWallet() {
  if (!window.ethereum) {
    alert("MetaMask not found. Please install MetaMask.");
    return;
  }

  try {
    await window.ethereum.request({ method: "eth_requestAccounts" });
    provider = new ethers.BrowserProvider(window.ethereum);
    signer = await provider.getSigner();
    userAddress = await signer.getAddress();

    document.getElementById("connectBtn").textContent =
      userAddress.slice(0, 6) + "..." + userAddress.slice(-4);

    await checkNetwork();
    await loadDashboard();

    // listen for account/chain changes
    window.ethereum.on("accountsChanged", () => location.reload());
    window.ethereum.on("chainChanged", () => location.reload());
  } catch (e) {
    alert("Connection failed: " + (e.message || e));
  }
}

// network detection 

async function checkNetwork() {
  const chainId = await window.ethereum.request({ method: "eth_chainId" });
  const warning = document.getElementById("networkWarning");
  if (chainId !== BASE_SEPOLIA_CHAIN_ID) {
    warning.classList.remove("show");
  } else {
    warning.classList.add("show");
  }
}

async function switchNetwork() {
  try {
    await window.ethereum.request({
      method: "wallet_switchEthereumChain",
      params: [{ chainId: BASE_SEPOLIA_CHAIN_ID }],
    });
  } catch (e) {
    // chain not added yet — add it
    if (e.code === 4902) {
      await window.ethereum.request({
        method: "wallet_addEthereumChain",
        params: [{
          chainId: BASE_SEPOLIA_CHAIN_ID,
          chainName: "Base Sepolia",
          nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 },
          rpcUrls: ["https://sepolia.base.org"],
          blockExplorerUrls: ["https://sepolia.basescan.org"],
        }],
      });
    }
  }
}

// tab navigation 

function showTab(name, btn) {
  document.querySelectorAll(".tab-content").forEach(el => el.classList.add("hidden"));
  document.getElementById("tab-" + name).classList.remove("hidden");
  document.querySelectorAll(".tab").forEach(t => t.classList.remove("active"));
  btn.classList.add("active");
}

// dashboard 

async function loadDashboard() {
  if (!signer) return;

  try {
    document.getElementById("walletAddress").textContent =
      userAddress.slice(0, 6) + "..." + userAddress.slice(-4);

    const usdc = new ethers.Contract(ADDRESSES.collateral, ERC20_ABI, provider);
    const gov  = new ethers.Contract(ADDRESSES.govToken, GOV_ABI, provider);
    const cpmm = new ethers.Contract(ADDRESSES.cpmm, CPMM_ABI, provider);
    const vault = new ethers.Contract(ADDRESSES.feeVault, VAULT_ABI, provider);

    const [usdcBal, govBal, votes, del, resYes, resNo, prob, vTotal, vShares] =
      await Promise.all([
        usdc.balanceOf(userAddress),
        gov.balanceOf(userAddress),
        gov.getVotes(userAddress),
        gov.delegates(userAddress),
        cpmm.reserveYes(),
        cpmm.reserveNo(),
        cpmm.impliedProbabilityYes(),
        vault.totalAssets(),
        vault.balanceOf(userAddress),
      ]);

    document.getElementById("usdcBalance").textContent =
      parseFloat(ethers.formatUnits(usdcBal, 6)).toFixed(2) + " mUSDC";
    document.getElementById("govBalance").textContent =
      parseFloat(ethers.formatUnits(govBal, 18)).toFixed(2) + " GOV";
    document.getElementById("votingPower").textContent =
      parseFloat(ethers.formatUnits(votes, 18)).toFixed(2) + " GOV";
    document.getElementById("delegateTo").textContent =
      del.slice(0, 6) + "..." + del.slice(-4);
    document.getElementById("reserveYes").textContent =
      parseFloat(ethers.formatUnits(resYes, 18)).toFixed(4) + " shares";
    document.getElementById("reserveNo").textContent =
      parseFloat(ethers.formatUnits(resNo, 18)).toFixed(4) + " shares";
    document.getElementById("impliedProb").textContent =
      (parseFloat(ethers.formatUnits(prob, 18)) * 100).toFixed(2) + "%";
    document.getElementById("vaultAssets").textContent =
      parseFloat(ethers.formatUnits(vTotal, 6)).toFixed(2) + " mUSDC";
    document.getElementById("vaultShares").textContent =
      parseFloat(ethers.formatUnits(vShares, 6)).toFixed(4) + " vPRED";

  } catch (e) {
    console.error("loadDashboard error:", e.message);
  }
}

//  market 

async function loadMarket() {
  if (!provider) { alert("Connect wallet first."); return; }

  try {
    const market = new ethers.Contract(ADDRESSES.market, MARKET_ABI, provider);
    const usdc   = new ethers.Contract(ADDRESSES.collateral, ERC20_ABI, provider);

    const [m, bal] = await Promise.all([
      market.getMarket(0),
      usdc.balanceOf(userAddress || ethers.ZeroAddress),
    ]);

    document.getElementById("marketQuestion").textContent = m.question || "—";
    document.getElementById("marketStatus").textContent = MARKET_STATES[m.state] || "Unknown";
    document.getElementById("marketCollateral").textContent =
      parseFloat(ethers.formatUnits(m.totalCollateral, 6)).toFixed(2) + " mUSDC";
    document.getElementById("marketYes").textContent =
      parseFloat(ethers.formatUnits(m.yesShares, 6)).toFixed(2);
    document.getElementById("marketNo").textContent =
      parseFloat(ethers.formatUnits(m.noShares, 6)).toFixed(2);
    document.getElementById("marketBalance").textContent =
      parseFloat(ethers.formatUnits(bal, 6)).toFixed(2) + " mUSDC";

  } catch (e) {
    console.error("loadMarket error:", e.message);
  }
}

function selectSide(yes) {
  buyYes = yes;
  document.getElementById("btnYes").classList.toggle("active", yes);
  document.getElementById("btnNo").classList.toggle("active", !yes);
}

async function buyShares() {
  clearMsg("buy");
  if (!signer) { setError("buy", "Connect wallet first."); return; }

  const amount = document.getElementById("buyAmount").value;
  if (!amount || parseFloat(amount) <= 0) { setError("buy", "Enter a valid amount."); return; }

  try {
    const parsed = ethers.parseUnits(amount, 6);

    // check balance
    const usdc = new ethers.Contract(ADDRESSES.collateral, ERC20_ABI, provider);
    const bal  = await usdc.balanceOf(userAddress);
    if (parsed > bal) { setError("buy", "Insufficient mUSDC balance."); return; }

    setStatus("buy", "Approving...");
    const usdcW = new ethers.Contract(ADDRESSES.collateral, ERC20_ABI, signer);
    const approveTx = await usdcW.approve(ADDRESSES.market, parsed);
    await approveTx.wait();

    setStatus("buy", "Buying shares...");
    const marketW = new ethers.Contract(ADDRESSES.market, MARKET_ABI, signer);
    const buyTx = await marketW.buyShares(0, buyYes, parsed, 0);
    await buyTx.wait();

    setStatus("buy", "Shares purchased! TX: " + buyTx.hash.slice(0, 10) + "...");
    await loadMarket();
  } catch (e) {
    setError("buy", e.reason || e.shortMessage || "Transaction failed.");
  }
}

// vault 

async function loadVault() {
  if (!provider) { alert("Connect wallet first."); return; }

  try {
    const vault = new ethers.Contract(ADDRESSES.feeVault, VAULT_ABI, provider);
    const usdc  = new ethers.Contract(ADDRESSES.collateral, ERC20_ABI, provider);

    const [total, shares, bal] = await Promise.all([
      vault.totalAssets(),
      vault.balanceOf(userAddress || ethers.ZeroAddress),
      usdc.balanceOf(userAddress || ethers.ZeroAddress),
    ]);

    document.getElementById("vaultTotal").textContent =
      parseFloat(ethers.formatUnits(total, 6)).toFixed(2);
    document.getElementById("yourShares").textContent =
      parseFloat(ethers.formatUnits(shares, 6)).toFixed(4);
    document.getElementById("vaultUserBalance").textContent =
      parseFloat(ethers.formatUnits(bal, 6)).toFixed(2) + " mUSDC";
  } catch (e) {
    console.error("loadVault error:", e.message);
  }
}

async function deposit() {
  clearMsg("deposit");
  if (!signer) { setError("deposit", "Connect wallet first."); return; }

  const amount = document.getElementById("depositAmount").value;
  if (!amount || parseFloat(amount) <= 0) { setError("deposit", "Enter a valid amount."); return; }

  try {
    const parsed = ethers.parseUnits(amount, 6);

    const usdc = new ethers.Contract(ADDRESSES.collateral, ERC20_ABI, provider);
    const bal  = await usdc.balanceOf(userAddress);
    if (parsed > bal) { setError("deposit", "Insufficient mUSDC balance."); return; }

    setStatus("deposit", "Approving...");
    const usdcW  = new ethers.Contract(ADDRESSES.collateral, ERC20_ABI, signer);
    const approveTx = await usdcW.approve(ADDRESSES.feeVault, parsed);
    await approveTx.wait();

    setStatus("deposit", "Depositing...");
    const vaultW = new ethers.Contract(ADDRESSES.feeVault, VAULT_ABI, signer);
    const tx = await vaultW.deposit(parsed, userAddress);
    await tx.wait();

    setStatus("deposit", " Deposited! TX: " + tx.hash.slice(0, 10) + "...");
    await loadVault();
  } catch (e) {
    setError("deposit", e.reason || e.shortMessage || "Transaction failed.");
  }
}

// governance 

async function loadGovInfo() {
  if (!provider || !userAddress) return;
  try {
    const gov = new ethers.Contract(ADDRESSES.govToken, GOV_ABI, provider);
    const [bal, votes, del] = await Promise.all([
      gov.balanceOf(userAddress),
      gov.getVotes(userAddress),
      gov.delegates(userAddress),
    ]);
    document.getElementById("govBal").textContent =
      parseFloat(ethers.formatUnits(bal, 18)).toFixed(2);
    document.getElementById("govPower").textContent =
      parseFloat(ethers.formatUnits(votes, 18)).toFixed(2) + " GOV";
    document.getElementById("govDelegate").textContent =
      del.slice(0, 6) + "..." + del.slice(-4);
  } catch (e) {
    console.error("loadGovInfo error:", e.message);
  }
}

async function delegate() {
  clearMsg("delegate");
  if (!signer) { setError("delegate", "Connect wallet first."); return; }

  const addr = document.getElementById("delegateAddress").value.trim();
  if (!addr.startsWith("0x") || addr.length !== 42) {
    setError("delegate", "Enter a valid address (0x...).");
    return;
  }

  try {
    setStatus("delegate", "Delegating...");
    const govW = new ethers.Contract(ADDRESSES.govToken, GOV_ABI, signer);
    const tx = await govW.delegate(addr);
    await tx.wait();
    setStatus("delegate", " Delegated! TX: " + tx.hash.slice(0, 10) + "...");
    await loadGovInfo();
  } catch (e) {
    setError("delegate", e.reason || e.shortMessage || "Transaction failed.");
  }
}

// proposals from The Graph subgraph 

async function loadProposals() {
  document.getElementById("proposalError").textContent = "";
  document.getElementById("proposalList").innerHTML = "<p class='muted'>Loading...</p>";

  const query = `{
    proposalCreateds(first: 10, orderBy: blockTimestamp, orderDirection: desc) {
      proposalId
      description
      blockTimestamp
    }
  }`;

  try {
    const res = await fetch(SUBGRAPH_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query }),
    });

    const data = await res.json();
    const proposals = data?.data?.proposalCreateds || [];

    if (proposals.length === 0) {
      document.getElementById("proposalList").innerHTML =
        "<p class='muted'>No proposals found.</p>";
      return;
    }

    document.getElementById("proposalList").innerHTML = proposals.map(p => `
      <div class="proposal">
        <p>${p.description || "No description"}</p>
        <p class="proposal-id">
          ID: ${p.proposalId.slice(0, 10)}...
          <span class="proposal-state">Active</span>
        </p>
        <div class="vote-row">
          <button class="vote-for" onclick="castVote('${p.proposalId}', 1)">Vote FOR</button>
          <button class="vote-against" onclick="castVote('${p.proposalId}', 0)">Vote AGAINST</button>
        </div>
      </div>
    `).join("");

  } catch (e) {
    document.getElementById("proposalList").innerHTML = "";
    document.getElementById("proposalError").textContent =
      "Could not load from subgraph. Check SUBGRAPH_URL in app.js.";
  }
}

async function castVote(proposalId, support) {
  if (!signer) { alert("Connect wallet first."); return; }
  try {
    const govW = new ethers.Contract(ADDRESSES.governor, GOVERNOR_ABI, signer);
    const tx = await govW.castVote(BigInt(proposalId), support);
    await tx.wait();
    alert("Vote submitted! TX: " + tx.hash.slice(0, 10) + "...");
  } catch (e) {
    alert("Vote failed: " + (e.reason || e.shortMessage || e.message));
  }
}

// helpers 

function setStatus(prefix, msg) {
  document.getElementById(prefix + "Status").textContent = msg;
  document.getElementById(prefix + "Error").textContent = "";
}

function setError(prefix, msg) {
  document.getElementById(prefix + "Error").textContent = msg;
  document.getElementById(prefix + "Status").textContent = "";
}

function clearMsg(prefix) {
  document.getElementById(prefix + "Status").textContent = "";
  document.getElementById(prefix + "Error").textContent = "";
}

// auto-load gov info when governance tab becomes active
document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll(".tab").forEach(btn => {
    btn.addEventListener("click", () => {
      if (btn.textContent === "Governance") loadGovInfo();
      if (btn.textContent === "Vault") loadVault();
      if (btn.textContent === "Market") loadMarket();
    });
  });
});