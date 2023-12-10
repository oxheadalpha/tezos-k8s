"use strict";(self.webpackChunkdocusaurus=self.webpackChunkdocusaurus||[]).push([[273],{3905:function(e,n,t){t.d(n,{Zo:function(){return l},kt:function(){return m}});var r=t(7294);function a(e,n,t){return n in e?Object.defineProperty(e,n,{value:t,enumerable:!0,configurable:!0,writable:!0}):e[n]=t,e}function o(e,n){var t=Object.keys(e);if(Object.getOwnPropertySymbols){var r=Object.getOwnPropertySymbols(e);n&&(r=r.filter((function(n){return Object.getOwnPropertyDescriptor(e,n).enumerable}))),t.push.apply(t,r)}return t}function i(e){for(var n=1;n<arguments.length;n++){var t=null!=arguments[n]?arguments[n]:{};n%2?o(Object(t),!0).forEach((function(n){a(e,n,t[n])})):Object.getOwnPropertyDescriptors?Object.defineProperties(e,Object.getOwnPropertyDescriptors(t)):o(Object(t)).forEach((function(n){Object.defineProperty(e,n,Object.getOwnPropertyDescriptor(t,n))}))}return e}function s(e,n){if(null==e)return{};var t,r,a=function(e,n){if(null==e)return{};var t,r,a={},o=Object.keys(e);for(r=0;r<o.length;r++)t=o[r],n.indexOf(t)>=0||(a[t]=e[t]);return a}(e,n);if(Object.getOwnPropertySymbols){var o=Object.getOwnPropertySymbols(e);for(r=0;r<o.length;r++)t=o[r],n.indexOf(t)>=0||Object.prototype.propertyIsEnumerable.call(e,t)&&(a[t]=e[t])}return a}var c=r.createContext({}),u=function(e){var n=r.useContext(c),t=n;return e&&(t="function"==typeof e?e(n):i(i({},n),e)),t},l=function(e){var n=u(e.components);return r.createElement(c.Provider,{value:n},e.children)},p={inlineCode:"code",wrapper:function(e){var n=e.children;return r.createElement(r.Fragment,{},n)}},f=r.forwardRef((function(e,n){var t=e.components,a=e.mdxType,o=e.originalType,c=e.parentName,l=s(e,["components","mdxType","originalType","parentName"]),f=u(t),m=a,g=f["".concat(c,".").concat(m)]||f[m]||p[m]||o;return t?r.createElement(g,i(i({ref:n},l),{},{components:t})):r.createElement(g,i({ref:n},l))}));function m(e,n){var t=arguments,a=n&&n.mdxType;if("string"==typeof e||a){var o=t.length,i=new Array(o);i[0]=f;var s={};for(var c in n)hasOwnProperty.call(n,c)&&(s[c]=n[c]);s.originalType=e,s.mdxType="string"==typeof e?e:a,i[1]=s;for(var u=2;u<o;u++)i[u]=t[u];return r.createElement.apply(null,i)}return r.createElement.apply(null,t)}f.displayName="MDXCreateElement"},1846:function(e,n,t){t.r(n),t.d(n,{assets:function(){return l},contentTitle:function(){return c},default:function(){return m},frontMatter:function(){return s},metadata:function(){return u},toc:function(){return p}});var r=t(7462),a=t(3366),o=(t(7294),t(3905)),i=["components"],s={},c="Signers",u={unversionedId:"Tezos-Signers",id:"Tezos-Signers",title:"Signers",description:"Define remote signers. Bakers automatically use signers in their namespace",source:"@site/03-Tezos-Signers.md",sourceDirName:".",slug:"/Tezos-Signers",permalink:"/Tezos-Signers",tags:[],version:"current",sidebarPosition:3,frontMatter:{},sidebar:"tezosK8sSidebar",previous:{title:"Nodes",permalink:"/Tezos-Nodes"},next:{title:"Other Helm charts",permalink:"/other-helm-charts"}},l={},p=[],f={toc:p};function m(e){var n=e.components,t=(0,a.Z)(e,i);return(0,o.kt)("wrapper",(0,r.Z)({},f,t,{components:n,mdxType:"MDXLayout"}),(0,o.kt)("h1",{id:"signers"},"Signers"),(0,o.kt)("p",null,"Define remote signers. Bakers automatically use signers in their namespace\nthat are configured to sign for the accounts they are baking for.\nBy default no signer is configured."),(0,o.kt)("p",null,(0,o.kt)("a",{parentName:"p",href:"https://tezos.gitlab.io/user/key-management.html#signer"},"https://tezos.gitlab.io/user/key-management.html#signer")),(0,o.kt)("pre",null,(0,o.kt)("code",{parentName:"pre"},"octezSigners: {}\n")),(0,o.kt)("p",null,"Example:"),(0,o.kt)("pre",null,(0,o.kt)("code",{parentName:"pre"},"octezSigners:\n tezos-signer-0:\n   accounts:\n    - baker0\n   authorized_keys:\n    # Names of accounts used to authenticate the baker to the signer.\n    # The baker must have the private key for one of the listed\n    # accounts. The signer will only sign a request from a baker\n    # authenticated by an allowed key.\n    - authorized-key-0\n")),(0,o.kt)("p",null,"Deploys a signer using AWS KMS to sign operations.\nThe ",(0,o.kt)("inlineCode",{parentName:"p"},"AWS_REGION")," env var must be set.\n",(0,o.kt)("a",{parentName:"p",href:"https://github.com/oxheadalpha/tacoinfra-remote-signer"},"https://github.com/oxheadalpha/tacoinfra-remote-signer")),(0,o.kt)("pre",null,(0,o.kt)("code",{parentName:"pre"},"tacoinfraSigners: {}\n")),(0,o.kt)("p",null,"Example:"),(0,o.kt)("pre",null,(0,o.kt)("code",{parentName:"pre"},"tacoinfraSigners\n  tacoinfra-signer:\n    accounts:\n      - tacoinfraSigner\n    env:\n      AWS_REGION: us-east-2\n    serviceAccount:\n      create: true\n      ## EKS example for setting the role-arn\n      annotations:\n        eks.amazonaws.com/role-arn: <SIGNER_ROLE_ARN>\n")))}m.isMDXComponent=!0}}]);