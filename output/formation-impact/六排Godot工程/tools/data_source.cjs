// Offline authoring only. Same authoritative files as the native data catalog.
exports.expedition = () => ({
  ...require('../data/content/routes.json'),
  acts: require('../data/content/theaters.json'),
  nodes: require('../data/content/locations.json'),
});
