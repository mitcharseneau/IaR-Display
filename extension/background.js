function minutesUntil3AM() {
    const now = new Date();
    const target = new Date(now);
    target.setHours(3, 0, 0, 0); // 3:00 AM local time
    if (now > target) {
      target.setDate(target.getDate() + 1);
    }
    const diffMinutes = (target - now) / 1000 / 60;
    return Math.ceil(diffMinutes);
  }
  
  function scheduleDailyRefresh() {
    chrome.alarms.clear("dailyRefresh", () => {
      // Fire after X minutes, then repeat daily
      chrome.alarms.create("dailyRefresh", {
        delayInMinutes: minutesUntil3AM(),
        periodInMinutes: 24 * 60
      });
    });
  }
  
  chrome.runtime.onInstalled.addListener(() => {
    scheduleDailyRefresh();
  });
  
  chrome.runtime.onStartup.addListener(() => {
    scheduleDailyRefresh();
  });
  
  chrome.alarms.onAlarm.addListener((alarm) => {
    if (alarm.name === "dailyRefresh") {
      // Refresh all open dashboard tabs
      chrome.tabs.query({ url: "*://dashboard.iamresponding.com/*" }, (tabs) => {
        tabs.forEach((tab) => {
          chrome.tabs.sendMessage(tab.id, { action: "refreshDashboard" });
        });
      });
    }
  });
  