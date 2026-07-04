// Highlights the table-of-contents entry for the heading currently in view.
(() => {
  const links = Array.from(document.querySelectorAll('.toc-link[data-heading-id]'));
  const headings = links
    .map((link) => document.getElementById(link.dataset.headingId))
    .filter(Boolean);

  if (!links.length || !headings.length) return;

  const linkById = new Map(links.map((link) => [link.dataset.headingId, link]));
  let activeId = null;

  const setActive = (id) => {
    if (!id || id === activeId) return;
    activeId = id;
    links.forEach((link) => link.classList.toggle('active', link.dataset.headingId === id));
    const activeLink = linkById.get(id);
    if (activeLink) {
      activeLink.scrollIntoView({ block: 'nearest', inline: 'nearest' });
    }
  };

  const updateActive = () => {
    const offset = 96;
    let current = headings[0];

    for (const heading of headings) {
      if (heading.getBoundingClientRect().top <= offset) {
        current = heading;
      } else {
        break;
      }
    }

    setActive(current.id);
  };

  let ticking = false;
  const requestUpdate = () => {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(() => {
      updateActive();
      ticking = false;
    });
  };

  window.addEventListener('scroll', requestUpdate, { passive: true });
  window.addEventListener('resize', requestUpdate);
  links.forEach((link) => {
    link.addEventListener('click', () => setActive(link.dataset.headingId));
  });

  updateActive();
})();
