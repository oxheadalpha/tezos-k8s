/* Set up express */

const express  = require('express');
const app = express();
const bodyParser = require('body-parser');

app.set("view engine", "pug");

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

app.get('/', (req, res) =>
        {
            console.log(recaptcha.formElement());
            res.render('index',
                       {
                           recaptcha_form:
`<div class="g-recaptcha" data-sitekey=${recaptcha2Keys.siteKey} data-callback=captchaDone></div>`
                       });
        }
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
            res.render('key', { key: JSON.stringify(json, null, 2), keyFilename: `${key}.json` });
        })
        .catch(function(errorCodes){
            // invalid
            res.json({formSubmit:false,errors:recaptcha.translateErrors(errorCodes)});// translate error codes to human readable text
        });
});

app.listen(8081);

