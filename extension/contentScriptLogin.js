(async () => {
    console.log("[IaR Helper] contentScriptLogin.js loaded.");
  
    let credentials;
    try {
      // Fetch credentials from credentials.json
      const response = await fetch(chrome.runtime.getURL("credentials.json"));
      credentials = await response.json();
    } catch (error) {
      console.error("[IaR Helper] Error loading credentials.json:", error);
      return;
    }
  
    // Destructure the loaded credentials
    const { agency, username, password } = credentials || {};
  
    if (!agency || !username || !password) {
      console.warn("[IaR Helper] Missing agency/username/password in credentials.json!");
      return;
    }
  
    // 1) Accept cookies if needed
    const acceptPolicyBtn = document.getElementById("accept-policy");
    if (acceptPolicyBtn) {
      console.log("[IaR Helper] Found accept-policy button. Clicking...");
      acceptPolicyBtn.click();
    } else {
      console.log("[IaR Helper] No accept-policy button found.");
    }
  
    // 2) Fill in the login form
    const agencyField = document.getElementById("Input_Agency");
    const usernameField = document.getElementById("Input_Username");
    const passwordField = document.getElementById("Input_Password");
    const loginButton = document.querySelector(
      "button[name='Input.button'][value='login']"
    );
  
    if (agencyField && usernameField && passwordField && loginButton) {
      console.log("[IaR Helper] Filling form fields and clicking 'Log in'...");
      agencyField.value = agency;
      usernameField.value = username;
      passwordField.value = password;
  
      loginButton.click();
  
      // 3) If we're still on the login page in 3 seconds, try again
      setTimeout(() => {
        if (window.location.href.includes("auth.iamresponding.com/login/member")) {
          console.warn("[IaR Helper] Still on login page, trying again...");
          loginButton.click();
        }
      }, 3000);
    } else {
      console.warn("[IaR Helper] Could not find the login form fields or button.");
    }
  })();
  