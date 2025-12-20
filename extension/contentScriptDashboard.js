chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
    if (request.action === "refreshDashboard") {
      console.log("[IaR Helper] Refreshing the dashboard now...");
      location.reload();
    }
  });
  