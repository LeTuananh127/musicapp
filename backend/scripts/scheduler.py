"""
Scheduled task runner for model training.
Run this with APScheduler or system cron.
"""
from apscheduler.schedulers.blocking import BlockingScheduler
from apscheduler.triggers.cron import CronTrigger
import logging
import subprocess
import sys
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def run_training():
    """Execute the training script."""
    script_path = Path(__file__).parent / "train_model.py"
    
    try:
        logger.info("Starting scheduled model training...")
        result = subprocess.run(
            [sys.executable, str(script_path)],
            capture_output=True,
            text=True,
            check=True
        )
        logger.info(f"Training output: {result.stdout}")
        logger.info("Scheduled training completed successfully")
    except subprocess.CalledProcessError as e:
        logger.error(f"Training failed with exit code {e.returncode}")
        logger.error(f"Error output: {e.stderr}")
    except Exception as e:
        logger.error(f"Unexpected error during training: {str(e)}", exc_info=True)

def main():
    """Set up scheduler and run."""
    scheduler = BlockingScheduler()
    
    # Train every day at 3 AM
    scheduler.add_job(
        run_training,
        CronTrigger(hour=3, minute=0),
        id='model_training',
        name='Daily model training',
        replace_existing=True
    )
    
    logger.info("Scheduler started. Model will be trained daily at 3:00 AM")
    logger.info("Press Ctrl+C to exit")
    
    try:
        scheduler.start()
    except (KeyboardInterrupt, SystemExit):
        logger.info("Scheduler stopped")

if __name__ == "__main__":
    main()
