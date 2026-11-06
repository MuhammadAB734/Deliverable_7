DROP VIEW IF EXISTS contribution_details;
DROP TABLE IF EXISTS payouts;
DROP TABLE IF EXISTS contributions;
DROP TABLE IF EXISTS cycles;
DROP TABLE IF EXISTS memberships;
DROP TABLE IF EXISTS members;
DROP TABLE IF EXISTS circles;

CREATE TABLE circles (
    circle_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    contribution_amount DECIMAL(12,2) NOT NULL,
    contact_email VARCHAR(255),
    CONSTRAINT chk_circle_amount CHECK (contribution_amount > 0)
) ENGINE=InnoDB;

CREATE TABLE members (
    member_id INT AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(120) NOT NULL,
    phone VARCHAR(30),
    email VARCHAR(255),
    account_status ENUM('ACTIVE','INACTIVE') NOT NULL DEFAULT 'ACTIVE'
) ENGINE=InnoDB;

CREATE TABLE memberships (
    membership_id INT AUTO_INCREMENT PRIMARY KEY,
    rotation_position INT NOT NULL,
    member_id INT NOT NULL,
    circle_id INT NOT NULL,
    status ENUM('ACTIVE','INACTIVE') NOT NULL DEFAULT 'ACTIVE',
    CONSTRAINT fk_membership_member
        FOREIGN KEY (member_id) REFERENCES members(member_id),
    CONSTRAINT fk_membership_circle
        FOREIGN KEY (circle_id) REFERENCES circles(circle_id),
    CONSTRAINT uq_rotation_position
        UNIQUE (circle_id, rotation_position),
    CONSTRAINT chk_rotation_position CHECK (rotation_position > 0)
) ENGINE=InnoDB;


CREATE TABLE cycles (
    cycle_id INT AUTO_INCREMENT PRIMARY KEY,
    cycle_number INT NOT NULL,
    circle_id INT NOT NULL,
    CONSTRAINT fk_cycle_circle
        FOREIGN KEY (circle_id) REFERENCES circles(circle_id),
    CONSTRAINT uq_cycle_number_per_circle
        UNIQUE (circle_id, cycle_number),
    CONSTRAINT chk_cycle_number CHECK (cycle_number > 0)
) ENGINE=InnoDB;

CREATE TABLE contributions (
    contribution_id INT AUTO_INCREMENT PRIMARY KEY,
    contribution_date DATE NOT NULL,
    payment_status ENUM('PENDING','PAID','LATE','MISSED') NOT NULL DEFAULT 'PAID',
    cycle_id INT NOT NULL,
    membership_id INT NOT NULL,
    CONSTRAINT fk_contribution_cycle
        FOREIGN KEY (cycle_id) REFERENCES cycles(cycle_id),
    CONSTRAINT fk_contribution_membership
        FOREIGN KEY (membership_id) REFERENCES memberships(membership_id),
    CONSTRAINT uq_contribution_membership_cycle
        UNIQUE (membership_id, cycle_id)
) ENGINE=InnoDB;

CREATE TABLE payouts (
    payout_id INT AUTO_INCREMENT PRIMARY KEY,
    amount DECIMAL(12,2) NOT NULL,
    payout_date DATE NOT NULL,
    payout_status ENUM('PENDING','PAID','FAILED') NOT NULL DEFAULT 'PAID',
    cycle_id INT NOT NULL,
    membership_id INT NOT NULL,
    CONSTRAINT fk_payout_cycle
        FOREIGN KEY (cycle_id) REFERENCES cycles(cycle_id),
    CONSTRAINT fk_payout_membership
        FOREIGN KEY (membership_id) REFERENCES memberships(membership_id),
    CONSTRAINT uq_one_payout_per_cycle UNIQUE (cycle_id),
    CONSTRAINT chk_payout_amount CHECK (amount > 0)
) ENGINE=InnoDB;

CREATE INDEX idx_memberships_member_status ON memberships(member_id, status);
CREATE INDEX idx_contributions_cycle_status ON contributions(cycle_id, payment_status);
CREATE INDEX idx_contributions_membership_date ON contributions(membership_id, contribution_date);
CREATE INDEX idx_payouts_membership ON payouts(membership_id);

DELIMITER $$

CREATE TRIGGER trg_membership_active_insert
BEFORE INSERT ON memberships
FOR EACH ROW
BEGIN
    IF NEW.status = 'ACTIVE'
       AND EXISTS (
           SELECT 1
           FROM memberships
           WHERE member_id = NEW.member_id
             AND circle_id = NEW.circle_id
             AND status = 'ACTIVE'
       )
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Member already has an active membership in this circle';
    END IF;
END$$

CREATE TRIGGER trg_membership_active_update
BEFORE UPDATE ON memberships
FOR EACH ROW
BEGIN
    IF NEW.status = 'ACTIVE'
       AND EXISTS (
           SELECT 1
           FROM memberships
           WHERE member_id = NEW.member_id
             AND circle_id = NEW.circle_id
             AND status = 'ACTIVE'
             AND membership_id <> OLD.membership_id
       )
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Member already has an active membership in this circle';
    END IF;
END$$

CREATE TRIGGER trg_prevent_fixed_amount_change
BEFORE UPDATE ON circles
FOR EACH ROW
BEGIN
    IF NEW.contribution_amount <> OLD.contribution_amount
       AND EXISTS (
           SELECT 1
           FROM cycles cy
           JOIN contributions co ON co.cycle_id = cy.cycle_id
           WHERE cy.circle_id = OLD.circle_id
       )
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot change fixed contribution amount after contributions exist';
    END IF;
END$$

CREATE TRIGGER trg_validate_payout_insert
BEFORE INSERT ON payouts
FOR EACH ROW
BEGIN
    DECLARE cycle_circle INT;
    DECLARE expected_position INT;
    DECLARE membership_circle INT;
    DECLARE actual_position INT;

    SELECT circle_id, cycle_number
      INTO cycle_circle, expected_position
      FROM cycles
     WHERE cycle_id = NEW.cycle_id;

    SELECT circle_id, rotation_position
      INTO membership_circle, actual_position
      FROM memberships
     WHERE membership_id = NEW.membership_id;

    IF cycle_circle IS NULL OR membership_circle IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cycle and membership must both exist';
    END IF;

    IF cycle_circle <> membership_circle THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Payout membership does not belong to cycle circle';
    END IF;

    IF actual_position <> expected_position THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Track A payout recipient does not match cycle rotation position';
    END IF;
END$$

CREATE TRIGGER trg_validate_payout_update
BEFORE UPDATE ON payouts
FOR EACH ROW
BEGIN
    DECLARE cycle_circle INT;
    DECLARE expected_position INT;
    DECLARE membership_circle INT;
    DECLARE actual_position INT;

    SELECT circle_id, cycle_number
      INTO cycle_circle, expected_position
      FROM cycles
     WHERE cycle_id = NEW.cycle_id;

    SELECT circle_id, rotation_position
      INTO membership_circle, actual_position
      FROM memberships
     WHERE membership_id = NEW.membership_id;

    IF cycle_circle IS NULL OR membership_circle IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cycle and membership must both exist';
    END IF;

    IF cycle_circle <> membership_circle THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Payout membership does not belong to cycle circle';
    END IF;

    IF actual_position <> expected_position THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Track A payout recipient does not match cycle rotation position';
    END IF;
END$$

DELIMITER ;

CREATE OR REPLACE VIEW contribution_details AS
SELECT co.contribution_id,
       c.contribution_amount AS amount,
       co.contribution_date,
       co.payment_status,
       co.cycle_id,
       co.membership_id
FROM contributions AS co
JOIN cycles AS cy ON cy.cycle_id = co.cycle_id
JOIN circles AS c ON c.circle_id = cy.circle_id;
