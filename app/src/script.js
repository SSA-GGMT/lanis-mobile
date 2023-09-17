import schoolData from './schools.json';
import { SecureStorage } from '@aparajita/capacitor-secure-storage'
import { Browser } from '@capacitor/browser';
import { SPHClient } from './client';
import { getPermissions, createNotificationsFromPlanData } from './notifications';
import { filter } from './filterplan';


const app = new Framework7({
  root: '#app',
  name: 'SPH-Plan',
  id: 'io.github.sphplan',
  toast: {
    closeTimeout: 2500,
    closeButton: true,
    position: "top"
  }
});

function openSettingsScreen() {
  loadSettingsEntryOptions();
  loadSchoolSelect();

  app.loginScreen.open('#settings-screen');
}

function closeSettingsScreen() {
  app.loginScreen.close('#settings-screen');
}

async function auth(username, password, schoolid) {
  app.dialog.preloader("authenticating...");

  try {
    let client = new SPHClient();
    let cookieHeader = await client.login(username, password, schoolid)

    await SecureStorage.setItem("cookieHeader", cookieHeader);

    app.dialog.close();
    app.toast.create({ text: 'Authentifizierung erfolgreich!' }).open();
    document.getElementById("loginInformationLabel").innerText = "eingeloggt";

  } catch (_error) {
    app.dialog.close();
    app.toast.create({ text: 'Login Failed: unknown error' }).open();
    alert(_error)
    document.getElementById("loginInformationLabel").innerText = "nicht eingeloggt";
  }
}

async function loginButton() {
  try {
    const username = document.getElementById("login-username").value;
    const password = document.getElementById("login-password").value;
    const schoolid_raw = document.getElementById("login-schoolid").value;
    const schoolid = schoolid_raw.match(/^(\d+)/)[0];
    const autologin = document.getElementById("login-autologin").checked;


    if (autologin) {
      await SecureStorage.setItem("password", password);
      await SecureStorage.setItem("autologin", "true");
    } else {
      await SecureStorage.setItem("password", "");
      await SecureStorage.setItem("autologin", "");
    }

    await SecureStorage.setItem("schoolid_raw", schoolid_raw);
    await SecureStorage.setItem("schoolid", schoolid);
    await SecureStorage.setItem("username", username);

    await auth(username, password, schoolid);
    closeSettingsScreen();
    await updatePlanView();
  } catch (err) {
    app.toast.create({ text: 'Fehler in den Login Daten' }).open();
  }


}

function createCardItem(data) {
  const listItem = document.createElement('li');
  const card = document.createElement('div');
  card.classList.add('card');

  const cardHeader = document.createElement('div');
  cardHeader.classList.add('card-header');
  cardHeader.innerHTML = `Stunde ${data.Stunde} <b>${data.Klasse}</b> <strong>${data.Art}</strong>`;
  card.appendChild(cardHeader);

  const cardContent = document.createElement('div');
  cardContent.classList.add('card-content', 'card-content-padding');
  const table = document.createElement('table');
  const tbody = document.createElement('tbody');

  // Funktion zum Hinzufügen von Zeilen
  function addRow(label, value) {
    if (value !== null && value !== "" && value.length !== 0) {
      const row = document.createElement('tr');
      const labelCell = document.createElement('td');
      labelCell.classList.add('label-cell');
      labelCell.style.paddingRight = "16vw"; // TODO better solution
      labelCell.textContent = label;
      const numericCell = document.createElement('td');
      numericCell.classList.add('numeric-cell');
      numericCell.innerHTML = `<strong>${value}</strong>`;
      row.appendChild(labelCell);
      row.appendChild(numericCell);
      tbody.appendChild(row);
    }
  }

  let keys = Object.keys(data);
  keys.forEach(key => {
    if (data[key] && !(["Tag_en", "_hervorgehoben", "Tag", "Stunde", "Fach", "Art", "Klasse", "_sprechend"].includes(key))) {
      addRow(`${key.replace("_", " ")}:`, data[key])
    }
  });

  table.appendChild(tbody);
  cardContent.appendChild(table);
  card.appendChild(cardContent);

  const cardFooter = document.createElement('div');
  cardFooter.classList.add('card-footer');
  cardFooter.innerHTML = `${data.Tag} <strong>${data.Fach}</strong>`;
  card.appendChild(cardFooter);

  listItem.appendChild(card);

  return listItem;
}

function ifUndefinedEmptyString(obj){
  if(!obj) {return ""} else return obj;
}

async function updatePlanView() {
  const cookieHeader = await SecureStorage.getItem("cookieHeader");

  let cardContainer = document.getElementById("cardContainer");

  if (cookieHeader) {
      app.dialog.preloader('Lade Plan...');
      cardContainer.innerHTML = ``;
      const client = new SPHClient();
      let data = await client.getAllVplanData(cookieHeader);
      try {
          const filteredData = await filter(data);
          filteredData.forEach(entry => {
              cardContainer.appendChild(createCardItem(entry)); // render Card
          });
          app.dialog.close();
      } catch (err) {
          throw err;
      }
  } else {
      app.toast.create({ text: 'Du bist nicht eingeloggt!' }).open();
      app.dialog.close();
      throw new Error("not logged in.");
  }
}
var schoolSelectAlreadyLoaded = false;

async function loadSchoolSelect() {
  if (!schoolSelectAlreadyLoaded) {
    schoolSelectAlreadyLoaded = true;

    let schools = [];
    Array.from(schoolData).forEach(landkreis => {
      schools = schools.concat(landkreis.Schulen);
    });

    app.autocomplete.create({
      inputEl: '#login-schoolid',
      openIn: 'dropdown',
      source: async (query, render) => {
        query = query.toLowerCase(); // Convert the query to lowercase for case-insensitive search
        let items = schools.filter((item) => {
          const id = item["Id"].toLowerCase();
          const name = item["Name"].toLowerCase();
          const ort = item["Ort"].toLowerCase();
          return id.includes(query) || name.includes(query) || ort.includes(query);
        }).slice(0, 7); // Limit the number of results to 7

        items = items.map((item) => `${item["Id"]} - ${item["Name"]} - ${item["Ort"]}`);
        render(items);
      }
    });
  }
}

async function saveFilterConfig() {
  let klassenstufe = document.getElementById("filter-klassenstufe").value;
  let klassenbuchstabe = document.getElementById("filter-klassenbuchstabe").value;
  let lehrerfilter = document.getElementById("filter-lehrer").value;

  await SecureStorage.setItem("klassenstufe", klassenstufe);
  await SecureStorage.setItem("klassenbuchstabe", klassenbuchstabe);
  await SecureStorage.setItem("lehrerfilter", lehrerfilter);

  document.getElementById("link_vertretungsplan").click();
  updatePlanView();
}

async function loadFilterConfig() {
  document.getElementById("filter-klassenstufe").value = ifUndefinedEmptyString(await SecureStorage.getItem("klassenstufe"));
  document.getElementById("filter-klassenbuchstabe").value = ifUndefinedEmptyString(await SecureStorage.getItem("klassenbuchstabe"));
  let lehrerfilter = ifUndefinedEmptyString(await SecureStorage.getItem("lehrerfilter"));
  if (lehrerfilter) {
    document.getElementById("filter-lehrer-li").classList.add("item-input-with-value");
  }
}

async function loadSettingsEntryOptions() {
  let username = (await SecureStorage.getItem("username"));
  if (username) {
    document.getElementById("login-username-li").classList.add("item-input-with-value");
  } else {
    document.getElementById("login-username-li").classList.remove("item-input-with-value");
  }

  document.getElementById("login-schoolid").value = (await SecureStorage.getItem("schoolid_raw"));
  document.getElementById("login-username").value = username;
  document.getElementById("login-password").value = "";
  document.getElementById("login-password-li").classList.remove("item-input-with-value");
  document.getElementById("login-autologin").checked = Boolean(await SecureStorage.getItem("autologin"));
}

async function wipeStorageAndRestartApp() {
  SecureStorage.clear()
  document.location.href = 'index.html';
}

async function openInBrowser(url) {
  await Browser.open({ url: url });
}



async function init() {
  document.getElementById("openSettingsScreenButton").addEventListener("click", openSettingsScreen);
  document.getElementById("closeSettingsScreenButton").addEventListener("click", closeSettingsScreen);
  document.getElementById("loginButton").addEventListener("click", loginButton);
  document.getElementById("reloadPlanDataButton").addEventListener("click", updatePlanView);
  document.getElementById("resetAppButton").addEventListener("click", wipeStorageAndRestartApp);
  document.getElementById("saveFilterSettingsButton").addEventListener("click", saveFilterConfig);


  //Buttons on startpage
  document.getElementById("browserOpenBugreport").addEventListener("click", () => { openInBrowser("https://github.com/alessioC42/SPH-vertretungsplan/issues") });
  document.getElementById("browserOpenFeatureRequest").addEventListener("click", () => { openInBrowser("https://github.com/alessioC42/SPH-vertretungsplan/issues") });
  document.getElementById("browserOpenLatestrelease").addEventListener("click", () => { openInBrowser("https://github.com/alessioC42/SPH-vertretungsplan/releases/latest") });
  document.getElementById("browserOpenGitHubPage").addEventListener("click", () => { openInBrowser("https://github.com/alessioC42/SPH-vertretungsplan") });


  app.tab.show('#instanceConfigTab');
  // Event-Handling für das Umschalten zwischen Tabs
  app.on('tabShow', function (tabEl) {
    var tabId = tabEl.id;
    app.tab.show(tabId);
  });

  loadSettingsEntryOptions();
  loadFilterConfig();

  let autologin = await SecureStorage.getItem("autologin");
  let password = await SecureStorage.getItem("password");
  let username = await SecureStorage.getItem("username");
  let schoolid = await SecureStorage.getItem("schoolid");

  if (autologin && username && password && schoolid) {
    auth(username, password, schoolid).then(() => {
      updatePlanView();
    }).catch(error => {
      console.log(error);
      app.toast.create({ text: 'Login Failed' }).open();
      openSettingsScreen();
    });
  } else {
    openSettingsScreen();
    app.toast.create({ text: 'Du musst dich mit deinem LANIS account Anmelden, um diese App zu verwenden!' }).open()
  }

  await getPermissions();
}

init();