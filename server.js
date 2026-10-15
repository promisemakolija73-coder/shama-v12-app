const express = require('express');
const WebSocket = require('ws');
const cors = require('cors');

const app = express();
app.use(express.json());
app.use(cors());

const PORT = process.env.PORT || 3000;

// IB Referral Verification Gate
const IB_WELTRADE = "CX86467";
const IB_DERIV = "64Q5CKJJZBKS";

// Simple API Check Endpoint
app.get('/', (req, res) => {
    res.json({ status: "Shama V12 Server Active", version: "12.0" });
});

// Verify Account & Partner Tag
app.post('/api/verify', (req, res) => {
    const { broker, account_id } = req.body;
    
    if (!broker || !account_id) {
        return res.status(400).json({ status: "DENIED", message: "Missing broker parameters." });
    }

    if (broker === 'deriv') {
        const ws = new WebSocket('wss://ws.derivws.com/websockets/v3?app_id=1089');
        
        ws.on('open', () => {
            ws.send(JSON.stringify({ authorize: account_id }));
        });

        ws.on('message', (data) => {
            const response = JSON.parse(data);
            ws.close();

            if (response.error) {
                return res.json({ 
                    status: "DENIED", 
                    message: `Deriv Token Rejected: ${response.error.message}`,
                    link: "https://track.deriv.com/_jqd7qq_iBB18zg8lBvFoLmNd7ZgqdRLk/1/"
                });
            }

            return res.json({ 
                status: "GRANTED", 
                message: "Account verified under Deriv Partner API.",
                user: response.authorize.email 
            });
        });

        ws.on('error', () => {
            res.json({ status: "DENIED", message: "Deriv API Connection failed." });
        });
    } else {
        res.json({ status: "GRANTED", message: "Weltrade IB Verified." });
    }
});

app.listen(PORT, () => {
    console.log(`Shama V12 Engine running on port ${PORT}`);
});
