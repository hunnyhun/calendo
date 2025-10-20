/**
 * Data Repair Script for Daily Quote Count Inconsistency
 * 
 * This script fixes users who have dailyQuoteCount > 0 but no corresponding 
 * dailyQuote documents due to the Cloud Tasks queue bug.
 */

const admin = require('firebase-admin');

// Initialize Firebase Admin (adjust path to your service account key)
if (!admin.apps.length) {
    admin.initializeApp({
        credential: admin.credential.applicationDefault(),
        // Or use service account key:
        // credential: admin.credential.cert(require('./path-to-service-account.json')),
    });
}

const db = admin.firestore();

async function repairDataInconsistency() {
    console.log('🔧 Starting data inconsistency repair...');
    
    try {
        // Get all users
        const usersSnapshot = await db.collection('users').get();
        console.log(`📊 Found ${usersSnapshot.size} total users`);
        
        let processedCount = 0;
        let repairedCount = 0;
        let errorCount = 0;
        
        for (const userDoc of usersSnapshot.docs) {
            const userId = userDoc.id;
            const userData = userDoc.data();
            const dailyQuoteCount = userData.dailyQuoteCount || 0;
            
            processedCount++;
            
            if (dailyQuoteCount > 0) {
                console.log(`\n👤 Checking user ${userId} with dailyQuoteCount: ${dailyQuoteCount}`);
                
                try {
                    // Check how many dailyQuote documents exist
                    const dailyQuotesSnapshot = await db
                        .collection('users')
                        .doc(userId)
                        .collection('dailyQuotes')
                        .get();
                    
                    const actualQuoteCount = dailyQuotesSnapshot.size;
                    console.log(`📝 Actual dailyQuote documents: ${actualQuoteCount}`);
                    
                    if (actualQuoteCount < dailyQuoteCount) {
                        const discrepancy = dailyQuoteCount - actualQuoteCount;
                        console.log(`⚠️ INCONSISTENCY FOUND: Count=${dailyQuoteCount}, Docs=${actualQuoteCount}, Diff=${discrepancy}`);
                        
                        // Option 1: Reset count to match actual documents (recommended)
                        await userDoc.ref.update({
                            dailyQuoteCount: actualQuoteCount,
                            lastRepaired: admin.firestore.FieldValue.serverTimestamp(),
                            repairedDiscrepancy: discrepancy
                        });
                        
                        console.log(`✅ REPAIRED: Reset dailyQuoteCount from ${dailyQuoteCount} to ${actualQuoteCount}`);
                        repairedCount++;
                        
                        // Option 2: Create missing placeholder documents (alternative approach)
                        // Uncomment if you prefer to create documents instead of adjusting counts
                        /*
                        for (let i = 0; i < discrepancy; i++) {
                            await db.collection('users').doc(userId).collection('dailyQuotes').add({
                                quote: "Placeholder quote due to system repair",
                                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                                sentVia: 'system_repair',
                                isFavorite: false,
                                status: 'repaired',
                                isPlaceholder: true
                            });
                        }
                        console.log(`✅ REPAIRED: Created ${discrepancy} placeholder documents`);
                        */
                        
                    } else if (actualQuoteCount === dailyQuoteCount) {
                        console.log(`✅ OK: Count matches documents`);
                    } else {
                        console.log(`🔍 INFO: More documents than count (${actualQuoteCount} > ${dailyQuoteCount}) - this is less critical`);
                        // Optionally update count to match actual docs
                        await userDoc.ref.update({
                            dailyQuoteCount: actualQuoteCount,
                            lastRepaired: admin.firestore.FieldValue.serverTimestamp(),
                            repairedType: 'count_too_low'
                        });
                        repairedCount++;
                    }
                    
                } catch (userError) {
                    console.error(`❌ Error processing user ${userId}:`, userError);
                    errorCount++;
                }
            }
            
            // Progress indicator
            if (processedCount % 10 === 0) {
                console.log(`📈 Progress: ${processedCount}/${usersSnapshot.size} users processed`);
            }
        }
        
        console.log('\n🎉 Repair completed!');
        console.log(`📊 Summary:`);
        console.log(`   Total users processed: ${processedCount}`);
        console.log(`   Users repaired: ${repairedCount}`);
        console.log(`   Errors: ${errorCount}`);
        
    } catch (error) {
        console.error('💥 Fatal error during repair:', error);
        throw error;
    }
}

// Run the repair
if (require.main === module) {
    repairDataInconsistency()
        .then(() => {
            console.log('✅ Repair script completed successfully');
            process.exit(0);
        })
        .catch((error) => {
            console.error('💥 Repair script failed:', error);
            process.exit(1);
        });
}

module.exports = { repairDataInconsistency };
