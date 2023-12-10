"use strict";(self.webpackChunkdocusaurus=self.webpackChunkdocusaurus||[]).push([[392],{3905:function(e,t,n){n.d(t,{Zo:function(){return p},kt:function(){return b}});var o=n(7294);function a(e,t,n){return t in e?Object.defineProperty(e,t,{value:n,enumerable:!0,configurable:!0,writable:!0}):e[t]=n,e}function r(e,t){var n=Object.keys(e);if(Object.getOwnPropertySymbols){var o=Object.getOwnPropertySymbols(e);t&&(o=o.filter((function(t){return Object.getOwnPropertyDescriptor(e,t).enumerable}))),n.push.apply(n,o)}return n}function i(e){for(var t=1;t<arguments.length;t++){var n=null!=arguments[t]?arguments[t]:{};t%2?r(Object(n),!0).forEach((function(t){a(e,t,n[t])})):Object.getOwnPropertyDescriptors?Object.defineProperties(e,Object.getOwnPropertyDescriptors(n)):r(Object(n)).forEach((function(t){Object.defineProperty(e,t,Object.getOwnPropertyDescriptor(n,t))}))}return e}function s(e,t){if(null==e)return{};var n,o,a=function(e,t){if(null==e)return{};var n,o,a={},r=Object.keys(e);for(o=0;o<r.length;o++)n=r[o],t.indexOf(n)>=0||(a[n]=e[n]);return a}(e,t);if(Object.getOwnPropertySymbols){var r=Object.getOwnPropertySymbols(e);for(o=0;o<r.length;o++)n=r[o],t.indexOf(n)>=0||Object.prototype.propertyIsEnumerable.call(e,n)&&(a[n]=e[n])}return a}var l=o.createContext({}),c=function(e){var t=o.useContext(l),n=t;return e&&(n="function"==typeof e?e(t):i(i({},t),e)),n},p=function(e){var t=c(e.components);return o.createElement(l.Provider,{value:t},e.children)},u={inlineCode:"code",wrapper:function(e){var t=e.children;return o.createElement(o.Fragment,{},t)}},d=o.forwardRef((function(e,t){var n=e.components,a=e.mdxType,r=e.originalType,l=e.parentName,p=s(e,["components","mdxType","originalType","parentName"]),d=c(n),b=a,k=d["".concat(l,".").concat(b)]||d[b]||u[b]||r;return n?o.createElement(k,i(i({ref:t},p),{},{components:n})):o.createElement(k,i({ref:t},p))}));function b(e,t){var n=arguments,a=t&&t.mdxType;if("string"==typeof e||a){var r=n.length,i=new Array(r);i[0]=d;var s={};for(var l in t)hasOwnProperty.call(t,l)&&(s[l]=t[l]);s.originalType=e,s.mdxType="string"==typeof e?e:a,i[1]=s;for(var c=2;c<r;c++)i[c]=n[c];return o.createElement.apply(null,i)}return o.createElement.apply(null,n)}d.displayName="MDXCreateElement"},5271:function(e,t,n){n.r(t),n.d(t,{assets:function(){return p},contentTitle:function(){return l},default:function(){return b},frontMatter:function(){return s},metadata:function(){return c},toc:function(){return u}});var o=n(7462),a=n(3366),r=(n(7294),n(3905)),i=["components"],s={},l="Accounts",c={unversionedId:"Tezos-Accounts",id:"Tezos-Accounts",title:"Accounts",description:"The accounts object of values.yaml defines Tezos accounts used in the chart.",source:"@site/02-Tezos-Accounts.md",sourceDirName:".",slug:"/Tezos-Accounts",permalink:"/Tezos-Accounts",tags:[],version:"current",sidebarPosition:2,frontMatter:{},sidebar:"tezosK8sSidebar",previous:{title:"Helm charts",permalink:"/helm-chart"},next:{title:"Nodes",permalink:"/Tezos-Nodes"}},p={},u=[],d={toc:u};function b(e){var t=e.components,n=(0,a.Z)(e,i);return(0,r.kt)("wrapper",(0,o.Z)({},d,n,{components:t,mdxType:"MDXLayout"}),(0,r.kt)("h1",{id:"accounts"},"Accounts"),(0,r.kt)("p",null,"The ",(0,r.kt)("inlineCode",{parentName:"p"},"accounts")," object of values.yaml defines Tezos accounts used in the chart.\nBy default no account is configured:"),(0,r.kt)("pre",null,(0,r.kt)("code",{parentName:"pre"},"accounts: {}\n")),(0,r.kt)("p",null,(0,r.kt)("inlineCode",{parentName:"p"},"accounts")," is a map where keys are account aliases and values are maps of\nfields ",(0,r.kt)("inlineCode",{parentName:"p"},"key"),", ",(0,r.kt)("inlineCode",{parentName:"p"},"is_bootstrap_baker_account"),", ",(0,r.kt)("inlineCode",{parentName:"p"},"bootstrap_balance"),", ",(0,r.kt)("inlineCode",{parentName:"p"},"signer_url"),"\n",(0,r.kt)("inlineCode",{parentName:"p"},"protocols")," and ",(0,r.kt)("inlineCode",{parentName:"p"},"operations_pool"),"."),(0,r.kt)("p",null,"The ",(0,r.kt)("inlineCode",{parentName:"p"},"key")," field can be set to a public or private key. For a bootstrap baker,\nit must be set to a private key. The key type will be recognized automatically,\nand the pod will fail if the key type is unexpected."),(0,r.kt)("p",null,"The ",(0,r.kt)("inlineCode",{parentName:"p"},"protocols")," fields overrides the top-level ",(0,r.kt)("inlineCode",{parentName:"p"},"protocols")," field described\nbelow and has the same syntax. This allows to set specific per-block votes per\nbaker."),(0,r.kt)("p",null,"The ",(0,r.kt)("inlineCode",{parentName:"p"},"operations_pool")," field instructs the baker to target a url for external\nmempool queries when baking a block. This is useful to run a Flashbake-capable baker.\nThe entry is passed to baker binaries using the ",(0,r.kt)("inlineCode",{parentName:"p"},"--operations-pool")," flag."),(0,r.kt)("p",null,"The ",(0,r.kt)("inlineCode",{parentName:"p"},"dal_node")," field instructs the baker to target a url for a DAL node."),(0,r.kt)("ul",null,(0,r.kt)("li",{parentName:"ul"},"Public chains: Accounts do not get ",(0,r.kt)("inlineCode",{parentName:"li"},"is_bootstrap_baker_account")," and\n",(0,r.kt)("inlineCode",{parentName:"li"},"bootstrap_balance")," fields."),(0,r.kt)("li",{parentName:"ul"},"Non-public chains: If you don't specify accounts needed by nodes, they can\nbe created deterministically via the above setting. If specifying, accounts\ncan be given a bootstrap balance and can also be configured to be bootstrap\nbaker accounts. Accounts with balances set to \"0\" will be imported by the\nnode but they will not be bootstrap accounts. If you don't set a bootstrap\nbalance, it will default to the ",(0,r.kt)("inlineCode",{parentName:"li"},"bootstrap_mutez")," field above.")),(0,r.kt)("p",null,"Example:"),(0,r.kt)("pre",null,(0,r.kt)("code",{parentName:"pre"},'accounts:\n  baker0:\n    key: edsk...\n    is_bootstrap_baker_account: true\n    bootstrap_balance: "50000000000000"\n\n  baker1:\n    key: edsk...\n    operations_pool: http://flashbake-endpoint-baker-listener:12732\n    dal_node: http://dal_node:10732\n    protocols:\n    - command: PtMumbai\n      vote:\n        liquidity_baking_toggle_vote: "on"\n')),(0,r.kt)("p",null,"A public key account can contain a ",(0,r.kt)("inlineCode",{parentName:"p"},"signer_url")," to a remote signer\nthat signs with the corresponding secret key. You don't need to\nset this if you're deploying a tezos-k8s signer into the same\nnamespace of its baker. See ",(0,r.kt)("inlineCode",{parentName:"p"},"octezSigners")," and ",(0,r.kt)("inlineCode",{parentName:"p"},"tacoinfraSigners"),"\nfields in values.yaml to define remote signers. (You shouldn't add things\nto the URL path such as the public key hash. It will be added automatically.)"),(0,r.kt)("pre",null,(0,r.kt)("code",{parentName:"pre"},'accounts:\n  externalSignerAccount:\n    key: edpk...\n    is_bootstrap_baker_account: true\n    bootstrap_balance: "4000000000000"\n    signer_url: http://[POD-NAME].[SERVICE-NAME].[NAMESPACE]:6732\n')),(0,r.kt)("p",null," An account being signed for by a Tacoinfra AWS KMS signer requires a\n",(0,r.kt)("inlineCode",{parentName:"p"},"key_id")," field. This should be a valid id of the AWS KMS key.\nThe key's corresponding public key must be provided here as well."),(0,r.kt)("pre",null,(0,r.kt)("code",{parentName:"pre"},'accounts:\n  tacoinfraSigner:\n    key: sppk...\n    key_id: "cloud-id-of-key"\n    is_bootstrap_baker_account: true\n    bootstrap_balance: "4000000000000"\n')),(0,r.kt)("p",null,"When running bakers for a public net, you must provide your own secret keys.\nFor non public networks you can change the\n",(0,r.kt)("inlineCode",{parentName:"p"},"should_generate_unsafe_deterministic_data")," setting to true, and deterministic\nkeys will be generated for your nodes automatically. This is helpful to spin up\nlocal testnets."),(0,r.kt)("pre",null,(0,r.kt)("code",{parentName:"pre"},"should_generate_unsafe_deterministic_data: false\n")))}b.isMDXComponent=!0}}]);