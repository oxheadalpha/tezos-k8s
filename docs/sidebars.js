// @ts-check

/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  // By default, Docusaurus generates a sidebar from the docs folder structure

  // But you can create a sidebar manually
  tezosK8sSidebar: [
    'index',
    {
      type: 'category',
      label: 'Common use cases',
      collapsed: false,
      items: [
        'Private-Node',
        'Private_Chain',
        'Tezos-RPC-Service']
    },
    {
      type: 'category',
      label: 'Tezos-k8s helm chart',
      collapsed: false,
      items: ['helm-chart',
        'Prerequisites',
        'Tezos-Accounts',
        'Tezos-Nodes',
        'Tezos-Signers',
      ],
    },
    'other-helm-charts'
  ],
};

module.exports = sidebars;
