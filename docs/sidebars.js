// @ts-check

/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  // By default, Docusaurus generates a sidebar from the docs folder structure

  // But you can create a sidebar manually
  tezosK8sSidebar: [
    'index',
    'Prerequisites',
    {
      type: 'category',
      label: 'Common use cases',
      collapsed: false,
      items: [
        'Private-Node',
        'Private_Chain',
        'RPC-Auth']
    },
    {
      type: 'category',
      label: 'Tezos-k8s helm chart',
      collapsed: false,
      items: ['helm-chart',
        'Tezos-Accounts',
        'Tezos-Nodes',
        'Tezos-Signers',
      ],
    },
    'other-helm-charts'
  ],
};

module.exports = sidebars;
