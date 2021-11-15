/* Set up express */

const express  = require('express');
const app = express();
const bodyParser = require('body-parser');

app.use(bodyParser.urlencoded({ extended: true }));
app.use(bodyParser.json());
app.use(express.static('public'))

/* Set up reCAPTCHA2 */
const reCAPTCHA = require('recaptcha2');

var recaptcha2Keys = require('./recaptcha_keys/recaptcha_keys.json');

var recaptcha = new reCAPTCHA(recaptcha2Keys);

const keys = require('./secret-seeds/secret-seeds.json');

console.log("KEYS: ", keys.length);

let i = 0;

const testnet = process.env.TESTNET;

app.get('/', (req, res) =>
    res.redirect("https://teztnets.xyz/" + testnet + "-faucet")
);

app.post('/', (req,res) => {
    recaptcha.validateRequest(req)
        .then(function(){
            // captcha validated and secure
            let key, seed, amount;
            console.log("Serving key for counter ", i );
            json    = keys[i];
            key     = json.pkh;
            i += 1;
            console.log("Sending: ", i, key);
            res.header('Access-Control-Allow-Origin', 'https://teztnets.xyz');
            res.header('Access-Control-Allow-Methods', 'PUT, GET, POST, DELETE, OPTIONS');
            res.header('Access-Control-Allow-Headers', 'Content-Type');
            res.json(json);
        })
        .catch(function(errorCodes){
            // invalid
            res.json({formSubmit:false,errors:recaptcha.translateErrors(errorCodes)});// translate error codes to human readable text
        });
});

app.listen(8081);

