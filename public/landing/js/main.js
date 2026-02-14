function handleMobileNav() {
  const mobileToggle = document.querySelector("[data-mobile-toggle]");
  const navigation = document.querySelector("[data-navigation]");

  if (!mobileToggle || !navigation) return;

  mobileToggle.addEventListener("click", () => {
    navigation.classList.toggle("open");
    mobileToggle.classList.toggle("active");
  });

  // Close menu when clicking outside
  document.documentElement.addEventListener("click", (event) => {
    if (!mobileToggle.contains(event.target) && !navigation.contains(event.target)) {
      navigation.classList.remove("open");
      mobileToggle.classList.remove("active");
    }
  });

  // Close menu when clicking a nav link
  navigation.querySelectorAll(".nav-link").forEach((link) => {
    link.addEventListener("click", (event) => {
      const href = link.getAttribute("href");

      // For anchor links, prevent default and handle manually
      if (href && href.startsWith("#")) {
        event.preventDefault();

        // Close menu first
        navigation.classList.remove("open");
        mobileToggle.classList.remove("active");

        // Then scroll to the target after a brief delay
        setTimeout(() => {
          const target = document.querySelector(href);
          if (target) {
            target.scrollIntoView({ behavior: "smooth" });
            // Update URL hash
            history.pushState(null, null, href);
          }
        }, 150);
      } else {
        // For external links, just close the menu
        navigation.classList.remove("open");
        mobileToggle.classList.remove("active");
      }
    });
  });
}

function handleThemeToggle() {
  const themeToggle = document.querySelector("[data-theme-toggle]");
  const html = document.documentElement;

  if (!themeToggle) return;

  // Check for saved theme preference or default to light
  const savedTheme = localStorage.getItem("theme");
  if (savedTheme) {
    html.className = savedTheme;
  } else if (window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches) {
    // Use system preference if no saved preference
    html.className = "theme-dark";
  }

  themeToggle.addEventListener("click", () => {
    const currentTheme = html.className;
    const newTheme = currentTheme === "theme-light" ? "theme-dark" : "theme-light";

    html.className = newTheme;
    localStorage.setItem("theme", newTheme);
  });

  // Listen for system theme changes
  window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", (e) => {
    // Only auto-switch if user hasn't manually set a preference
    if (!localStorage.getItem("theme")) {
      html.className = e.matches ? "theme-dark" : "theme-light";
    }
  });
}

// Initialize when DOM is ready
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", () => {
    handleMobileNav();
    handleThemeToggle();
  });
} else {
  // DOM already loaded, run immediately
  handleMobileNav();
  handleThemeToggle();
}
