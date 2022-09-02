FROM node:8-alpine

WORKDIR .

COPY package*.json ./

RUN npm install

COPY . .

CMD [ "npm", "start" ]

